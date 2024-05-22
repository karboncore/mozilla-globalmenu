#!/bin/sh

########################################################################################################################
# This script takes the Arch stable thunderbird PKGBUILD, revises it to add the appmenu/menubar patches, and optionally
# builds the modified thunderbird.
########################################################################################################################

# Download current PKGBUILD from Arch
wget -q -O- https://gitlab.archlinux.org/archlinux/packaging/packages/thunderbird/-/archive/main/thunderbird-main.tar.gz | \
  tar -xzf - --strip-components=1

# Download menubar patch from firefox-appmenu-112.0-1
wget -q -N https://raw.githubusercontent.com/archlinux/aur/1ab4aad0eaaa2f5313aee62606420b0b92c3d238/unity-menubar.patch

# Revise unity-menubar.patch to v115
patch -s -p1 <<'EOF'
--- firefox/unity-menubar.patch        2023-11-06 23:21:47.000000000 -0500
+++ firefox2/unity-menubar.patch     2024-05-20 12:28:21.251811335 -0400
@@ -1436,7 +1436,7 @@
 +
 +    mEventListener = new DocEventListener(this);
 +
-+    mDocument = do_QueryInterface(ContentNode()->OwnerDoc());
++    mDocument = ContentNode()->OwnerDoc();
 +
 +    mAccessKey = Preferences::GetInt("ui.key.menuAccessKey");
 +    if (mAccessKey == dom::KeyboardEvent_Binding::DOM_VK_SHIFT) {
EOF

# Save original PKGBUILD
cp PKGBUILD PKGBUILD.orig

# Revise maintainer string on PKGBUILD
printf "Enter maintainer string: "
read -r maintainer
if [[ -n $maintainer ]]; then
  sed -i "s/# Maintainer:/# Contributor:/g;
          1i # Maintainer: $maintainer" PKGBUILD
fi

# Get number of sources
n=$(sed -n '/^source/,/)/p' PKGBUILD | wc -l)

# Don't build language packs
sed -ni '/^_package_i18n()/,/^sha512sums/{/^sha512sums/!d};
         1,/^sha512sums/{/^sha512sums/!p};
         /^sha512sums/,+'$n'p' PKGBUILD
echo "            )" >> PKGBUILD

# Default to -globalmenu suffix
printf "Append -globalmenu to package name? [Y/n] "
read -r ans
if [[ "$ans" != n && "$ans" != no ]]; then
  sed -i 's/$pkgname/$pkgbase/g;
          s/pkgname=(thunderbird)/pkgname=($pkgbase-globalmenu)/g;
          s/package_thunderbird()/package()/g' PKGBUILD
  printf "
provides=(thunderbird)
conflicts=(thunderbird)" >> PKGBUILD
fi

# Add menubar patches
echo "
source+=(unity-menubar.patch)
sha512sums+=(b606e350fd702e1ae8c2813ec9c752e9395fe87a98d2e0b8f5223158decdc08b52f948b8ec9a51d4e354ad0aec017f22f9546f761f9242e94a5189718903209a)" \
>> PKGBUILD

# Build
printf "PKGBUILD generated. Continue with build? [y/N] "
read -r ans
if [[ "$ans" == y || "$ans" == yes ]]; then
  if [[ -z $(gpg --locate-keys E36D3B13F3D93274) ]]; then
    printf "Add E36D3B13F3D93274 to keyring? [y/N] "
    read -r ans
    if [[ "$ans" == y || "$ans" == yes ]]; then
      gpg --keyserver hkps://keys.openpgp.org/ --recv-keys E36D3B13F3D93274
    fi
  fi
  makepkg -s
fi
