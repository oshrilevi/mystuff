# MyStuff

Native macOS + iPhone app to track everything you own. Data is stored in your Google Sheet and photos in Google Drive.

## Setup

### 1. Google Cloud Console

1. Create a project at [Google Cloud Console](https://console.cloud.google.com).
2. Enable **Google Sheets API** and **Google Drive API** (APIs & Services → Library).
3. **OAuth consent screen** (APIs & Services → OAuth consent screen):
   - User type: **External** (so you can add test users).
   - Fill App name (e.g. “My Stuff”), support email, developer contact.
   - Under **Scopes**, add if needed: `.../auth/spreadsheets`, `.../auth/drive.file`.
   - **Important:** Leave the app in **Testing** (do not publish to production). Under **Test users**, click **+ ADD USERS** and add **your Google account email**. Only listed test users can sign in; no Google verification is required.
4. Create credentials: **OAuth 2.0 Client ID** → application type **iOS** → bundle ID **`com.mystuff.inventory`** → copy **Client ID**. (Use this one client for both iPhone and Mac.)

### 2. Xcode project

1. Open **MyStuff.xcodeproj** in Xcode (double-click or File → Open).
2. Add the Google Sign-In package: **File → Add Package Dependencies**. Enter:
   - `https://github.com/google/GoogleSignIn-iOS`
   - Add both **GoogleSignIn** and **GoogleSignInSwift** to the **MyStuff** target (Frameworks, Libraries, and Embedded Content).
3. Build and run (⌘R).

### 3. Info.plist – fix “400” or “malformed” on sign-in

The **400. That’s an error** (or “malformed request”) on the login screen means the app is still using the placeholder Google Client ID. You must use your real OAuth Client ID from Google Cloud.

1. In **Google Cloud Console** → your project → **APIs & Services** → **Credentials**, create an **OAuth 2.0 Client ID**:
   - Application type: **iOS** (there is no separate “macOS” option – Google uses **iOS** for both iPhone and Mac apps). Bundle ID: **`com.mystuff.inventory`** (must match Xcode). Copy the **Client ID**. These credentials have **no client secret** – that’s correct.
   - If you see **“client secret is missing”**: you’re using a Web or Desktop client. Create a **new** credential with type **iOS** and use that Client ID in Info.plist.

2. In Xcode, open **MyStuff/Info.plist** (in the Project navigator).

3. Set **GIDClientID**:
   - Replace the value with your **full** iOS Client ID, e.g. `123456789012-abcdefghij.apps.googleusercontent.com`. The same Client ID works for both iPhone and Mac.

4. Set **CFBundleURLSchemes** (under **CFBundleURLTypes** → Item 0 → **CFBundleURLSchemes** → Item 0):
   - Value must be: `com.googleusercontent.apps.` **+** the part of your Client ID **before** `.apps.googleusercontent.com`.
   - Example: if Client ID is `123456789012-abcdefghij.apps.googleusercontent.com`, the scheme is:  
     `com.googleusercontent.apps.123456789012-abcdefghij`
   - So replace `com.googleusercontent.apps.YOUR_IOS_CLIENT_ID` with that string (no spaces, no `.apps.googleusercontent.com` at the end).

5. Save, then build and run again. Sign-in should no longer return 400.

### 4. Run

- Select the **MyStuff** scheme and a destination (iPhone Simulator or My Mac).
- Build and run. Sign in with Google; the app will create a spreadsheet and a Drive folder on first run.

### If the build fails

- **"Xcode failed to provision this target"** / **automatic signing can’t create a valid profile**:  
  1. In Xcode: **MyStuff** target → **Signing & Capabilities** → set **Team** and leave **Automatically manage signing** on.  
  2. **Product → Clean Build Folder** (⇧⌘K), then build (⌘B).  
  3. If it still fails, try running on **My Mac** or **iPhone 15 Simulator** (not a physical device) to see if the error is device-specific.  
  4. To reset signing: turn **Automatically manage signing** off, then on again, and pick your Team. Build again.
- **"has entitlements that require signing"** / **"requires a development team"**: In Xcode → **MyStuff** target → **Signing & Capabilities** → choose your **Team**. Then build again (⌘B).
- **"No such module 'GoogleSignIn'"**: Add the package (see step 2 above): File → Add Package Dependencies → `https://github.com/google/GoogleSignIn-iOS`, then add **GoogleSignIn** and **GoogleSignInSwift** to the MyStuff target.

### If the app builds but Google sign-in fails after changing the bundle ID

The OAuth client in Google Cloud is tied to a **bundle ID**. The app now uses **`com.mystuff.inventory`**.

- In **Google Cloud Console** → **APIs & Services** → **Credentials**, either:
  - **Edit** your existing iOS OAuth client and set its bundle ID to **`com.mystuff.inventory`**, or  
  - **Create a new** iOS OAuth client with bundle ID **`com.mystuff.inventory`**, then in **MyStuff/Info.plist** set **GIDClientID** to the new client’s Client ID and **CFBundleURLSchemes** to `com.googleusercontent.apps.` + the part of that Client ID before `.apps.googleusercontent.com`.
- Without this, Google will reject sign-in because the app’s bundle ID and the OAuth client’s bundle ID must match.

### "Access blocked: ... has not completed the Google verification process"

Your Google account must be allowed to use the app while it’s in testing.

1. In **Google Cloud Console** go to **APIs & Services** → **OAuth consent screen**.
2. Leave **Publishing status** as **Testing** (do not set to “In production” unless you plan to submit for verification).
3. Scroll to **Test users** → click **+ ADD USERS**.
4. Add the **exact Google account email** you use to sign in (e.g. `you@gmail.com`).
5. Save. Try signing in again in the app; it may take a minute to apply.

## Features

- Sign in with Google.
- Items: name, description, category, price, purchase date, condition, photos.
- Categories: add, list, delete.
- Gallery: grid of items, search, filter by category, tap for detail, add/edit with photo upload.
