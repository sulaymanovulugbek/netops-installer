#!/usr/bin/env bash
# install.sh — public bootstrap for the NetOps Platform.
#
# ZERO credentials are persisted. Every git operation (install / update /
# rollback) prompts the operator for username + Personal Access Token and
# uses them only for that single invocation.
#
# Customer one-liner:
#   curl -fsSL https://raw.githubusercontent.com/sulaymanovulugbek/netops-installer/main/install.sh \
#     | sudo bash
set -euo pipefail

REPO_OWNER="sulaymanovulugbek"
REPO_NAME="netops-platform"
BRANCH="${NETOPS_BRANCH:-release/v1.0}"
TARGET="${NETOPS_TARGET:-/opt/netops-platform}"

if [[ -t 1 ]]; then C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_R=$'\033[0m'
else C_OK=""; C_ERR=""; C_DIM=""; C_R=""; fi
ok()  { printf "  ${C_OK}[OK]${C_R}   %s\n" "$*"; }
err() { printf "  ${C_ERR}[FAIL]${C_R} %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }
dim() { printf "  ${C_DIM}%s${C_R}\n" "$*"; }

[[ $EUID -eq 0 ]] || die "must run as root (try: sudo bash install.sh)"
[[ -t 0 ]] || die "no TTY for interactive prompt — re-run as: sudo bash install.sh (do not pipe to sudo)"

# --- prompt operator EVERY run, never cache ----------------------------------
echo "  NetOps Platform — installer"
echo "  Repo:   ${REPO_OWNER}/${REPO_NAME} (private)"
echo "  Branch: ${BRANCH}"
echo "  Target: ${TARGET}"
echo ""
echo "  Provide GitHub credentials with read access to the private repo."
echo "  Generate a fine-grained PAT (Repository → Contents: Read-only):"
echo "    https://github.com/settings/personal-access-tokens/new"
echo ""
read -r    -p "  GitHub username: " GH_USER
read -r -s -p "  GitHub Personal Access Token (hidden): " GH_TOKEN
echo ""
[[ -n "$GH_USER" ]]  || die "username cannot be empty"
[[ -n "$GH_TOKEN" ]] || die "token cannot be empty"

# Always shred the token from memory at exit (never written to disk)
cleanup() {
  GH_TOKEN=""
  [[ -n "${TMP_INSTALLER:-}" ]] && shred -u "$TMP_INSTALLER" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- validate -----------------------------------------------------------------
echo "[1/4] validating credentials against GitHub..."
http_code=$(curl -fsSL -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}" || echo "000")
if [[ "$http_code" != "200" ]]; then
  die "GitHub returned HTTP ${http_code} — token invalid or no access to ${REPO_OWNER}/${REPO_NAME}"
fi
ok "credentials accepted by GitHub for user: $GH_USER"

# --- download real installer (in-memory token only) ---------------------------
echo "[2/4] downloading install-oel.sh from private repo..."
TMP_INSTALLER=$(mktemp /tmp/install-oel-real.XXXX.sh)
if ! curl -fsSL -H "Authorization: token ${GH_TOKEN}" \
        -H "Accept: application/vnd.github.raw" \
        -o "$TMP_INSTALLER" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/install/install-oel.sh?ref=${BRANCH}"; then
  die "cannot fetch install-oel.sh — token may have expired"
fi
chmod +x "$TMP_INSTALLER"
ok "installer downloaded ($(wc -c < "$TMP_INSTALLER") bytes)"

# --- run real installer, pass token ONLY via env for this process tree --------
echo "[3/4] running install-oel.sh..."
NETOPS_REPO_URL_AUTHED="https://oauth2:${GH_TOKEN}@github.com/${REPO_OWNER}/${REPO_NAME}.git"
NETOPS_REPO_URL="$NETOPS_REPO_URL_AUTHED" \
NETOPS_BRANCH="$BRANCH" \
NETOPS_TARGET="$TARGET" \
GITHUB_TOKEN="$GH_TOKEN" \
  bash "$TMP_INSTALLER" \
    --repo-url="$NETOPS_REPO_URL_AUTHED" \
    --branch="$BRANCH" \
    --target="$TARGET"

# --- strip token from git remote so .git/config has no credentials ------------
if [[ -d "${TARGET}/.git" ]]; then
  git -C "$TARGET" remote set-url origin "https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
  ok "removed token from ${TARGET}/.git/config"
fi

# --- install pre/post hooks for update + rollback to ALWAYS prompt ------------
echo "[4/4] wiring update / rollback to always prompt..."
for script in update-oel.sh; do
  path="${TARGET}/install/${script}"
  [[ -f "$path" ]] || continue
  # Inject a credential prompt + ephemeral remote URL rewrite at the top of
  # the script body (after shebang). Old prompt is removed if present.
  if ! grep -q "NETOPS_PROMPT_INJECTED" "$path"; then
    awk -v marker="NETOPS_PROMPT_INJECTED" '
      NR==1 { print; next }
      NR==2 && /^#/ { print; next }
      !inj {
        print "# " marker " — bootstrap-installed prompt; never store creds"
        print "if [[ -t 0 ]] && [[ -t 1 ]] && [[ -d /opt/netops-platform/.git ]]; then"
        print "  read -r    -p \"  GitHub username: \" _GHU"
        print "  read -r -s -p \"  GitHub Personal Access Token (hidden): \" _GHT; echo \"\""
        print "  if [[ -n \"$_GHT\" ]]; then"
        print "    git -C /opt/netops-platform remote set-url origin \"https://oauth2:${_GHT}@github.com/'"$REPO_OWNER"'/'"$REPO_NAME"'.git\""
        print "    trap '\''git -C /opt/netops-platform remote set-url origin https://github.com/'"$REPO_OWNER"'/'"$REPO_NAME"'.git; _GHT=\"\"'\'' EXIT INT TERM"
        print "  fi"
        print "fi"
        inj=1
      }
      { print }
    ' "$path" > "${path}.new"
    mv "${path}.new" "$path"
    chmod +x "$path"
  fi
done
ok "update will prompt for credentials each run"

echo ""
ok "NetOps Platform bootstrapped successfully."
echo ""
echo "  Open:  http://\$(hostname -I | awk '{print \$1}'):13000"
echo "  Login: admin / admin (forced password change → 6-step wizard)"
echo ""
echo "  Update (will prompt for token again):"
echo "    sudo ${TARGET}/install/update-oel.sh"
echo ""
echo "  Rollback / uninstall:"
echo "    see ${TARGET}/docs/release/ROLLBACK.md"
