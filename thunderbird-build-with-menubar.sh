#!/bin/sh

########################################################################################################################
# This script takes the Arch stable thunderbird PKGBUILD, revises it to add the appmenu/menubar patches, and optionally
# builds the modified thunderbird.
########################################################################################################################

# Current version and baseline commit
commit=0809a5ea478b4fde738abb83c0fb30481659ea8e
version=$(wget -q -O- https://archive.mozilla.org/pub/thunderbird/releases/|sed '/href/!d;s@.*releases/@@g;s@/.*@@g;/b/d'|sort -n|tail -1)
sha512=$(wget -q -O- https://archive.mozilla.org/pub/thunderbird/releases/$version/SHA512SUMS|awk '/thunderbird-130.0.source.tar.xz/{print $1}')

# Check for existing files
if [[ -f PKGBUILD.orig && -f unity-menubar.orig ]]; then
  printf "Existing files found. Re-download? [y/N] "
  read -r ans
else
  ans=yes
fi

if [[ "$ans" == y || "$ans" == yes ]]; then
  # Download current PKGBUILD from Arch
  wget -q -O- https://gitlab.archlinux.org/archlinux/packaging/packages/thunderbird/-/archive/$commit/thunderbird-$commit.tar.gz | \
  tar -xzf - --strip-components=1

  # Download menubar patch from firefox-appmenu-112.0-1
  wget -q -N https://raw.githubusercontent.com/archlinux/aur/1ab4aad0eaaa2f5313aee62606420b0b92c3d238/unity-menubar.patch

  # Save original PKGBUILD and menubar patch
  cp PKGBUILD PKGBUILD.orig
  cp unity-menubar.patch unity-menubar.orig
else
  # Reuse existing files
  cp PKGBUILD.orig PKGBUILD
  cp unity-menubar.orig unity-menubar.patch
fi

# Revise PKGBUILD to v130
sed --in-place "s/pkgver=.*/pkgver=${version}/g;
                s/b12e1302d6be94dd88bee6dd069d3fec944bfce95e1afc1d72c14cc188d952fd5a85f0e70575317250701ac89498d876f3384b022957689fabcef61ad7d78c29/$sha512/g;
                /63de65c2d98287dea2db832a870764f621c25bf0c1353d16f8e68e8316e7554d2047b1c7bbb74a6c48de423f6201964491cd89564e5142066b6609a1aed941a7/d;
                /346fc7c2bcdf0708f41529886a542d2cf11a02799ef2a69dddfa2c6449b8bd7309033f3893f78f21c4ea0be3f35741e12b448977c966f2ae5a0087f9e0465864/d;
                /249706b68ce2450e35216b615b24b7640e75dd120d6d866fa8aab03d644fa6c40b5e129740874d96608bd0c187b6f2456d0d4310729d26d4740d1eca753be4fd/d;
                /7bc7969fe03e5cee0ddb844f7917154afdc4a4df8b8af9c8191180a6813faca9f310cf6b689ec358bc45af12fa3ec386cd46cb9feecf9b38557e36552aa0572d/d;
                /0031-bmo-1873379-fix-libc++-18-ignore-tuple-harder.patch/d;
                /0032-bmo-1841919-llvm-18-variable-does-not-need-to-be-mutable.patch/d;
                /0033-bmo-1882209-update-crates-for-rust-1.78-stripped-patch-from-bugs.freebsd.org-bug278834.patch/d;
                /0034-bgo-936072-update-crates-for-rust-1.78-patch-from-bugs.freebsd.org-bug278989.patch/d;
                s@_FORTIFY_SOURCE=3/_FORTIFY_SOURCE=2}@_FORTIFY_SOURCE=3/_FORTIFY_SOURCE=2} -fno-exceptions@g" PKGBUILD

# Revise unity-menubar.patch to v129
patch --no-backup-if-mismatch -s -p1 <<'EOF'
--- firefox/unity-menubar.patch        2024-08-09 21:36:17.726612101 -0400
+++ firefox2/unity-menubar.patch     2024-08-09 21:36:31.643601143 -0400
@@ -1,19 +1,3 @@
---- a/browser/base/content/browser-menubar.inc
-+++ b/browser/base/content/browser-menubar.inc
-@@ -7,7 +7,12 @@
- # On macOS, we don't track whether activation of the native menubar happened
- # with the keyboard.
- #ifndef XP_MACOSX
--                onpopupshowing="if (event.target.parentNode.parentNode == this)
-+                onpopupshowing="if (event.target.parentNode.parentNode == this &amp;&amp;
-+#ifdef MOZ_WIDGET_GTK
-+                                    document.documentElement.getAttribute('shellshowingmenubar') != 'true')
-+#else
-+                                    true)
-+#endif
-                                   this.setAttribute('openedwithkey',
-                                                     event.target.parentNode.openedWithKey);"
- #endif
 --- a/browser/base/content/browser.js
 +++ b/browser/base/content/browser.js
 @@ -6466,11 +6466,18 @@ function onViewToolbarsPopupShowing(aEve
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
@@ -3006,7 +3006,7 @@
 +#endif /* __nsMenuItem_h__ */
 --- /dev/null
 +++ b/widget/gtk/nsMenuObject.cpp
-@@ -0,0 +1,653 @@
+@@ -0,0 +1,654 @@
 +/* -*- Mode: C++; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */
 +/* vim:expandtab:shiftwidth=4:tabstop=4:
 + */
@@ -3243,7 +3243,8 @@
 +                          nullptr, 0, loadGroup, this, nullptr, nullptr,
 +                          nsIRequest::LOAD_NORMAL, nullptr,
 +                          nsIContentPolicy::TYPE_IMAGE, EmptyString(),
-+                          false, false, 0, getter_AddRefs(mImageRequest));
++                          false, false, 0, dom::FetchPriority::Auto,
++                          getter_AddRefs(mImageRequest));
 +    }
 +}
 +
@@ -5121,33 +5122,21 @@
  ]
  
  if defined('NS_PRINTING'):
---- a/xpfe/appshell/AppWindow.cpp
-+++ b/xpfe/appshell/AppWindow.cpp
-@@ -80,7 +80,7 @@
- 
- #include "mozilla/dom/DocumentL10n.h"
- 
--#ifdef XP_MACOSX
-+#if defined(XP_MACOSX) || defined(MOZ_WIDGET_GTK)
- #  include "mozilla/widget/NativeMenuSupport.h"
- #  define USE_NATIVE_MENUS
- #endif
 --- a/widget/gtk/NativeMenuSupport.cpp
 +++ b/widget/gtk/NativeMenuSupport.cpp
-@@ -7,6 +7,8 @@
- 
- #include "MainThreadUtils.h"
+@@ -10,6 +10,8 @@
  #include "NativeMenuGtk.h"
+ #include "DBusMenu.h"
+ #include "nsWindow.h"
 +#include "nsINativeMenuService.h"
 +#include "nsServiceManagerUtils.h"
  
  namespace mozilla::widget {
  
-@@ -14,7 +16,14 @@ void NativeMenuSupport::CreateNativeMenu
+@@ -17,6 +19,14 @@ void NativeMenuSupport::CreateNativeMenu
                                              dom::Element* aMenuBarElement) {
    MOZ_RELEASE_ASSERT(NS_IsMainThread(),
                       "Attempting to create native menu bar on wrong thread!");
--  // TODO
 +
 +  nsCOMPtr<nsINativeMenuService> nms =
 +      do_GetService("@mozilla.org/widget/nativemenuservice;1");
@@ -5156,9 +5145,9 @@
 +  }
 +
 +  nms->CreateNativeMenuBar(aParent, aMenuBarElement);
- }
  
- already_AddRefed<NativeMenu> NativeMenuSupport::CreateNativeContextMenu(
+ #ifdef MOZ_ENABLE_DBUS
+   if (aMenuBarElement && StaticPrefs::widget_gtk_global_menu_enabled() &&
 --- /dev/null
 +++ b/widget/gtk/NativeMenuSupport.h
 @@ -0,0 +1,31 @@
EOF

# Revise maintainer string
printf "Enter maintainer string: "
read -r maintainer
if [[ -n $maintainer ]]; then
  sed -i "s/# Maintainer:/# Contributor:/g;
          1i # Maintainer: $maintainer" PKGBUILD
fi

# Pull sources directly from Arch
sed --in-place '/source=/i commit=https://gitlab.archlinux.org/archlinux/packaging/packages/thunderbird/-/raw/'$commit PKGBUILD
sed --in-place -nE '/source=/,/\)/{/ +https/!{s@ +@        $commit/@g}};p' PKGBUILD

# Get number of sources and skip language packs
n=$(( $(sed -n '/^source/,/)/p' PKGBUILD | wc -l) - 1 ))
sed -ni '/^_package_i18n()/,/^sha512sums/{/^sha512sums/!d};
         1,/^sha512sums/{/^sha512sums/!p};
         /^sha512sums/,+'$n'p' PKGBUILD
echo "            )" >> PKGBUILD

# Default to -globalmenu suffix
printf "Append -globalmenu to package name? [Y/n] "
read -r ans
if [[ "$ans" != n && "$ans" != no ]]; then
  sed -i 's@pkgname=.*@pkgname=thunderbird-globalmenu@g;
          s@$pkgname@thunderbird@g;
          /pkgbase=/d;
          s@package_thunderbird@package@g' PKGBUILD
  cat <<'EOF' >> PKGBUILD
provides=(thunderbird)
conflicts=(thunderbird)
EOF
fi

# Add menubar patches
echo "
source+=(unity-menubar.patch)
sha512sums+=(4215758f26d0b6045c549908b659e5b1e353886b483d6b7ff4757d93d45e4704eba886f51162202a048bd557fbdfe6e08b81f3b5cb493199635a188a0508c840)" \
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
