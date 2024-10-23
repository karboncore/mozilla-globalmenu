#!/bin/sh

########################################################################################################################
# This script takes the Arch stable firefox PKGBUILD, revises it to add the appmenu/menubar patches, and optionally
# builds the modified firefox.
########################################################################################################################

# Check for existing files
if [[ -f PKGBUILD.orig && -f unity-menubar.orig ]]; then
  printf "Existing files found. Re-download? [y/N] "
  read -r ans
else
  ans=yes
fi

if [[ "$ans" == y || "$ans" == yes ]]; then
  # Download current PKGBUILD from Arch
  wget -q -O- https://gitlab.archlinux.org/archlinux/packaging/packages/firefox/-/archive/main/firefox-main.tar.gz | \
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

# Revise unity-menubar.patch to v131
patch --no-backup-if-mismatch -s -p1 <<'EOF'
--- firefox/unity-menubar.patch  2024-10-18 07:24:17.830307950 -0400
+++ firefox2/unity-menubar.patch 2024-10-18 07:34:35.611460127 -0400
@@ -1,40 +1,3 @@
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
---- a/browser/base/content/browser.js
-+++ b/browser/base/content/browser.js
-@@ -6466,11 +6466,18 @@ function onViewToolbarsPopupShowing(aEve
-   MozXULElement.insertFTLIfNeeded("browser/toolbarContextMenu.ftl");
-   let firstMenuItem = aInsertPoint || popup.firstElementChild;
-   let toolbarNodes = gNavToolbox.querySelectorAll("toolbar");
-+
-+  let shellShowingMenubar = document.documentElement.getAttribute("shellshowingmenubar") == "true";
-+
-   for (let toolbar of toolbarNodes) {
-     if (!toolbar.hasAttribute("toolbarname")) {
-       continue;
-     }
- 
-+    if (shellShowingMenubar && toolbar.id == "toolbar-menubar") {
-+      continue;
-+    }
-+
-     if (toolbar.id == "PersonalToolbar") {
-       let menu = BookmarkingUI.buildBookmarksToolbarSubmenu(toolbar);
-       popup.insertBefore(menu, firstMenuItem);
 --- a/browser/components/places/content/places.xhtml
 +++ b/browser/components/places/content/places.xhtml
 @@ -165,6 +165,7 @@
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
commit=$(git ls-remote https://gitlab.archlinux.org/archlinux/packaging/packages/firefox.git HEAD|awk '{print $1}')
sed --in-place '/source=/i commit=https://gitlab.archlinux.org/archlinux/packaging/packages/firefox/-/raw/'$commit PKGBUILD
sed --in-place -nE '/source=/,/\)/{/ +https/!{s@ +@  $commit/@g}};p' PKGBUILD

# Add menubar patches
patch --no-backup-if-mismatch -s -p1 <<'EOF'
--- firefox/PKGBUILD	2023-08-30 02:15:49.000000000 -0400
+++ firefox2/PKGBUILD	2023-09-09 10:04:52.241855178 -0400
@@ -98,6 +98,9 @@
   mkdir mozbuild
   cd firefox-$pkgver
 
+  # Appmenu patches
+  patch -Np1 -i ../unity-menubar.patch
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
source+=('unity-menubar.patch')
sha256sums+=('95e69805c3f83aaf18ac18339289ba4661538c65b92ab93a352cb5bb76131c8a')
b2sums+=('3576e8f301a59a8d3713984455d9219d4512659e198e132b4acff7ffab0cdb7a0ebbfea68212b68cf5579b841a8a81e1b1ff4755340414430d32c4b7f4481b56')
EOF

# Default to -globalmenu suffix
printf "Append -globalmenu to package name? [Y/n] "
read -r ans
if [[ "$ans" != n && "$ans" != no ]]; then
  sed -i 's@pkgname=firefox@pkgname=firefox-globalmenu@g;
          s@$pkgname@firefox@g;
          s@${pkgname//-/_}@firefox@g' PKGBUILD
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
