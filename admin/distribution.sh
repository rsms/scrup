#!/bin/bash
set -o errexit

PROJECT_IDENTIFIER='Scrup'
ARCHIVE_URL_BASE='http://data.hunch.se/scrup/'
APPCAST_SSH_BASE='s.rsms:/var/s.rsms/www/scrup/'

BUNDLE_PATH="$1"
if [ "$BUNDLE_PATH" = "" ]; then
  echo "Usage: $0 <app bundle path>"
  echo "Example:"
  echo "  $0 build/Release/$PROJECT_IDENTIFIER.app"
  exit 123
fi

#BUILD_TAG="$("$BUNDLE_PATH/Contents/MacOS/"* --build-tag)"
BUNDLE_PARENT_DIR="$(dirname "$BUNDLE_PATH")"
BUNDLE_FILENAME="$(basename "$BUNDLE_PATH")"
REVISION=$(git rev-parse --short HEAD | sed -E 's/[^0-9a-f]+//g')
VERSION=$(plutil -convert json -o /dev/stdout "$BUNDLE_PATH/Contents/Info.plist" | sed -E 's/^.*CFBundleVersion":"([^"]+).*$/\1/g')
if [ "$BUILD_TAG" != "" ]; then BUILD_TAG="$BUILD_TAG-"; fi
ARCHIVE_FILENAME="$PROJECT_IDENTIFIER-${BUILD_TAG}$VERSION-$REVISION.zip"
KEYCHAIN_PRIVKEY_NAME="$PROJECT_IDENTIFIER release signing key (private)"

WD=$PWD
cd "$BUNDLE_PARENT_DIR"

echo "Creating '$ARCHIVE_FILENAME'"
rm -f "$ARCHIVE_FILENAME"
ditto -ck --keepParent "$BUNDLE_FILENAME" "$ARCHIVE_FILENAME"

# Check so that version is not released already
python - <<EOF
# encoding: utf-8
import sys, re

f = open('$WD/admin/appcast.xml','r')
APPCAST = f.read()
f.close()

if r'sparkle:version="$VERSION"' in APPCAST:
  print >> sys.stderr, 'Version $VERSION is already in admin/appcast.xml -- you need to'\
                       ' manually remove the entry and run this scrip again'
  sys.exit(1)
EOF

# Sign
echo "Signing '$ARCHIVE_FILENAME' with key '$KEYCHAIN_PRIVKEY_NAME'"

# For OS X ==10.7:
ARCHIVE_SIGNATURE=$(openssl dgst -sha1 -binary < "$ARCHIVE_FILENAME" | openssl dgst -dss1 -sign <(security find-generic-password -g -s "$KEYCHAIN_PRIVKEY_NAME" 2>&1 | grep 'password: ' | sed -E 's/^.+("<\?xml)/\1/g' | /usr/bin/perl -pe '($_) = /"(.+)"/; s/\\012/\n/g' | /usr/bin/perl -MXML::LibXML -e 'print XML::LibXML->new()->parse_file("-")->findvalue(q(//string[preceding-sibling::key[1] = "NOTE"]))') | openssl enc -base64
)

if [ "$ARCHIVE_SIGNATURE" = "" ]; then
  echo "Signing failed" >&2
  false
fi

ARCHIVE_URL="${ARCHIVE_URL_BASE}${ARCHIVE_FILENAME}"
ARCHIVE_SIZE=$(stat -f %z "$ARCHIVE_FILENAME")
ARCHIVE_PUBDATE=$(LC_TIME=c date +"%a, %d %b %G %T %z")

python - <<EOF
# encoding: utf-8
import sys, re
ITEM = '''
    <item>
      <title>Version $VERSION</title>
      <pubDate>$ARCHIVE_PUBDATE</pubDate>
      <enclosure
        url="$ARCHIVE_URL"
        sparkle:version="$VERSION"
        type="application/octet-stream"
        length="$ARCHIVE_SIZE"
        sparkle:dsaSignature="$ARCHIVE_SIGNATURE"
      />
    </item>
'''
f = open('$WD/admin/appcast.xml','r')
APPCAST = f.read()
f.close()

APPCAST = re.compile(r'(\n[ \r\n\t]*</channel>)', re.M).sub(ITEM.rstrip()+r'\1', APPCAST)
open('$WD/admin/appcast.xml','w').write(APPCAST)
EOF


cat <<EOF

                  ------------- INSTRUCTIONS -------------

1. Commit, tag and push the source

  git commit -am 'Release $VERSION'
  git tag -m 'Release $VERSION' 'v$VERSION'
  git push origin master --tags

2. Upload the archive:

  $ARCHIVE_URL

3. Publish the appcast:

  scp '$WD/admin/appcast.xml' ${APPCAST_SSH_BASE}appcast.xml

EOF
