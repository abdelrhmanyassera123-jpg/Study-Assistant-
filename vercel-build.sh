#!/usr/bin/env bash
set -e

if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi
export PATH="$PATH:$(pwd)/flutter/bin"

flutter doctor
flutter pub get
flutter build web --release

# لوحة التحكم (admin/) بتتنشر على /admin في نفس الموقع — مشروع Flutter لوحده
# بيتبني بعد الموقع ويتنسخ جوه ناتجه.
# The dashboard (admin/) is served at /admin on the same site: a separate
# Flutter project built after the site and copied into its output.
(
  cd admin
  flutter pub get
  flutter build web --release --base-href /admin/
)
rm -rf build/web/admin
cp -r admin/build/web build/web/admin
