#!/bin/sh

########################################################################################################################
# This script takes the Arch stable firefox PKGBUILD, revises it to add the appmenu/menubar patches, and optionally
# builds the modified firefox.
########################################################################################################################

# Download current PKGBUILD from Arch
wget -q -O- https://gitlab.archlinux.org/archlinux/packaging/packages/firefox/-/archive/main/firefox-main.tar.gz | \
  tar -xzf - --strip-components=1

# Download menubar patch from firefox-appmenu-112.0-1
wget -q -N https://raw.githubusercontent.com/archlinux/aur/1ab4aad0eaaa2f5313aee62606420b0b92c3d238/unity-menubar.patch

# Revise unity-menubar.patch to v125
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

# Generate fix_csd_window_buttons.patch
cat << EOF > fix_csd_window_buttons.patch
--- a/browser/base/content/browser.css
+++ b/browser/base/content/browser.css
@@ -334,5 +334,5 @@ toolbar[customizing] #whats-new-menu-button {
 %ifdef MENUBAR_CAN_AUTOHIDE
 #toolbar-menubar[autohide=true]:not([inactive]) + #TabsToolbar > .titlebar-buttonbox-container {
-  visibility: hidden;
+  visibility: visible;
 }
 %endif
EOF

# Save original PKGBUILD
cp PKGBUILD PKGBUILD.orig

# Revise maintainer string
printf "Enter maintainer string: "
read -r maintainer
if [[ -n $maintainer ]]; then
  sed -i "s/# Maintainer:/# Contributor:/g;
          1i # Maintainer: $maintainer" PKGBUILD
fi

# Add menubar patches
patch -s -p1 <<'EOF'
--- firefox/PKGBUILD	2023-08-30 02:15:49.000000000 -0400
+++ firefox2/PKGBUILD	2023-09-09 10:04:52.241855178 -0400
@@ -98,6 +98,10 @@
   mkdir mozbuild
   cd firefox-$pkgver
 
+  # Appmenu patches
+  patch -Np1 -i ../unity-menubar.patch
+  patch -Np1 -i ../fix_csd_window_buttons.patch
+
   echo -n "$_google_api_key" >google-api-key
   echo -n "$_mozilla_api_key" >mozilla-api-key
 
EOF
! (($?)) || exit 1

# Compilation with PGO may fail without a powerful PC
printf "Disable PGO? [Y/n] "
read -r ans
if [[ "$ans" != n && "$ans" != no ]]; then
  sed -ni '/3-tier PGO/,/Building optimized browser/d;
           /--with-pgo/d;
           /--enable-profile-use/d;
           s/--enable-lto.*/--enable-lto=cross,thin/g;
           p' PKGBUILD
fi

sed -i '/# vim/d' PKGBUILD

cat <<'EOF' >> PKGBUILD
source+=('unity-menubar.patch'
         'fix_csd_window_buttons.patch')
sha256sums+=('db34163af3d0a1fb8aec0b9fdcea18b6a8c2c7f352fa6c6fba2673c38fff2e47'
             '72b897d8a07e7cf3ddbe04a7e0a5bb577981d367c12f934907898fbf6ddf03e4')
b2sums+=('0e8e615dd9e0c2fa0ea1ddfb4256095a3164da90a6499e332516e5efa1563cf3a267376cdbc4b416b626b4cbbaa34cafc02610a8651782c0cf4d276c7dff9b7c'
         'bafaf2663380ab7ba1c4a03c49debc965f4197a35058a5066be421eae172dd9cc5ba7ae7a26a9fd0c9f1d4c9a7670f425261071e01f71e7641531568754baf74')
EOF

# Default to -globalmenu suffix
printf "Append -globalmenu to package name? [Y/n] "
read -r ans
if [[ "$ans" != n && "$ans" != no ]]; then
  sed -i '/pkgname=firefox/i pkgbase=firefox
       s/pkgname=firefox/pkgname=$pkgbase-globalmenu/g;
       s/$pkgname/$pkgbase/g;
       s/${pkgname/${pkgbase/g' PKGBUILD
  cat <<'EOF' >> PKGBUILD
provides=(firefox)
conflicts=(firefox)
EOF
fi

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
