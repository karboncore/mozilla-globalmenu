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
--- a/unity-menubar.patch	2024-11-06 20:46:56.993394170 -0500
+++ b/unity-menubar.patch	2024-11-06 20:48:45.754699871 -0500
@@ -1,50 +1,14 @@
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
-@@ -165,6 +165,7 @@
+@@ -186,7 +186,7 @@
+               onpopupshowing="document.getElementById('placeContent').focus()"
+               data-l10n-id="places-organize-button-mac"
  #else
-       <menubar id="placesMenu">
+-      <menubar id="placesMenu">
++      <menubar id="placesMenu" _moz-menubarkeeplocal="true">
          <menu class="menu-iconic" data-l10n-id="places-organize-button"
-+              _moz-menubarkeeplocal="true"
  #endif
                id="organizeButton">
-           <menupopup id="organizeButtonPopup">
 --- a/dom/xul/XULPopupElement.cpp
 +++ b/dom/xul/XULPopupElement.cpp
 @@ -208,6 +208,10 @@ void XULPopupElement::GetState(nsString&
@@ -1436,7 +1400,7 @@
 +
 +    mEventListener = new DocEventListener(this);
 +
-+    mDocument = do_QueryInterface(ContentNode()->OwnerDoc());
++    mDocument = ContentNode()->OwnerDoc();
 +
 +    mAccessKey = Preferences::GetInt("ui.key.menuAccessKey");
 +    if (mAccessKey == dom::KeyboardEvent_Binding::DOM_VK_SHIFT) {
@@ -3006,7 +2970,7 @@
 +#endif /* __nsMenuItem_h__ */
 --- /dev/null
 +++ b/widget/gtk/nsMenuObject.cpp
-@@ -0,0 +1,653 @@
+@@ -0,0 +1,654 @@
 +/* -*- Mode: C++; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */
 +/* vim:expandtab:shiftwidth=4:tabstop=4:
 + */
@@ -3243,7 +3207,8 @@
 +                          nullptr, 0, loadGroup, this, nullptr, nullptr,
 +                          nsIRequest::LOAD_NORMAL, nullptr,
 +                          nsIContentPolicy::TYPE_IMAGE, EmptyString(),
-+                          false, false, 0, getter_AddRefs(mImageRequest));
++                          false, false, 0, dom::FetchPriority::Auto,
++                          getter_AddRefs(mImageRequest));
 +    }
 +}
 +
@@ -5121,33 +5086,21 @@
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
@@ -5156,9 +5109,9 @@
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
sha256sums+=('b8b123a1b3d189dd053f68fc5e6075339131b9927be01e67151acd39b751e71f')
b2sums+=('d37c568e3f618d5ad94e26dcfa1c081fe6885f97267e0cf7e2f4fa16a744e16a13e11a5c5b6ae6d4fc6ac2725af1c0e3a5b1b8a430e25452f588737bf809f90e')
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
