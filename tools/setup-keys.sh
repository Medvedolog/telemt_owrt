#!/bin/sh
# Create the persistent author package key and release-manifest key, upload the
# private halves to GitHub secrets, and keep the public halves for feed intake.
set -eu

REPO="${REPO:-Medvedolog/telemt_owrt}"
OWFEED_VERSION="${OWFEED_VERSION:-v0.5.1}"
WORK="${WORK:-./keys-setup}"

command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login" >&2; exit 1; }

[ ! -e "$WORK" ] || {
    echo "$WORK already exists; do not generate a second signing identity by accident" >&2
    exit 1
}
mkdir -p "$WORK"

if command -v owfeed >/dev/null 2>&1; then
    OWFEED=$(command -v owfeed)
else
    case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    case "$(uname -s)" in
        Linux) os=linux ;;
        Darwin) os=darwin ;;
        *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac
    echo ">> downloading owfeed $OWFEED_VERSION"
    curl -fsSL -o "$WORK/owfeed" \
        "https://github.com/owfeed/owfeed/releases/download/$OWFEED_VERSION/owfeed-$os-$arch"
    chmod 0755 "$WORK/owfeed"
    OWFEED="$WORK/owfeed"
fi

"$OWFEED" keygen -force -o "$WORK/telemt-sign.pem"
"$OWFEED" keygen -force -usign -o "$WORK/telemt-release.key"

gh secret set TELEMT_SIGN_KEY --repo "$REPO" < "$WORK/telemt-sign.pem"
gh secret set TELEMT_USIGN_KEY --repo "$REPO" < "$WORK/telemt-release.key"

for name in TELEMT_SIGN_KEY TELEMT_USIGN_KEY; do
    gh secret list --repo "$REPO" | awk '{print $1}' | grep -Fxq "$name" || {
        echo "GitHub Actions secret was not created: $name" >&2
        exit 1
    }
done

mkdir -p keys
cp "$WORK/telemt-sign.pub.pem" keys/telemt-sign.pub.pem
cp "$WORK/telemt-release.pub" keys/telemt-release.pub

cat <<MSG
Signing identity created for $REPO.

PRIVATE — save outside the repository/password manager, then delete $WORK:
  $WORK/telemt-sign.pem
  $WORK/telemt-release.key

PUBLIC — commit these files BEFORE the next release tag:
  keys/telemt-sign.pub.pem
  keys/telemt-release.pub

Suggested commands:
  git add keys/telemt-sign.pub.pem keys/telemt-release.pub
  git commit -m "chore: add owfeed author signing keys"
  git push

GitHub secrets set:
  TELEMT_SIGN_KEY
  TELEMT_USIGN_KEY

Do not rotate these keys for an ordinary release. A feed pins the public key.
MSG
