# Changelog

All notable changes to the app are documented here. When releasing, update the version in Xcode (target → General) and add an entry below.

Format: **[Version] (YYYY-MM-DD)** with sections Added / Changed / Fixed / Removed as needed.

---

## [Unreleased]

- **Added:** User-controlled stores. Stores are stored in the Google Sheet (new **Stores** sheet), like Categories and Locations. In **Settings → Stores** you can add, edit, and remove stores (name, start URL, icon). The **Stores** section in the sidebar lists your stores and opens each in the in-app browser. New spreadsheets are seeded with Amazon, AliExpress, and B&H Photo; existing spreadsheets get the Stores sheet on first load. Last-visited URL per store remains in UserDefaults (`mystuff_browser_<storeId>`).
- **Added:** Thumbnail cache for Drive images. Item photos are cached in memory (NSCache) and on disk (`Caches/MyStuffThumbnails/`). Repeat views and app relaunches load from cache, reducing latency and Google Drive API usage. Disk cache is capped at 300 MB with oldest-files-first eviction.
- **Added:** AliExpress as a new store. **AliExpress** tab/sidebar entry opens aliexpress.com in the in-app browser; “Add this item” and “Extract from link” work as for other stores. Metadata extraction strips AliExpress-specific title/description boilerplate.
- **Added:** B&H Photo Video as a second store. New **B&H** tab/sidebar entry (with Amazon) opens bhphotovideo.com in the in-app browser; “Add this item” and “Extract from link” work as for Amazon. Metadata extraction strips B&H-specific title boilerplate.
- **Added:** Browse Amazon in-app. New **Amazon** tab with an embedded browser (WKWebView) and optional region picker (e.g. Amazon.com, Amazon.co.uk). Toolbar “Add this item” opens the add-item form with the current page URL prefilled and metadata extracted (title, description, price, tags) via existing “Extract from link.” Add-item form supports an optional initial URL (e.g. `ItemFormView(mode: .add(initialWebLink: url))`) for this flow.
- **Added:** Location support. Every item has an optional location. A new **Locations** tab lets you define locations and set one as the default for new items. Location is shown in the item form, detail view, list rows, and gallery popover.
- **Added:** Per-category color. Users can assign a color to each category in the Categories tab (edit → Header color). The main Items list and Gallery use that color as the category section header background.

---

## Example

## [1.0.0] (2025-01-15)

- Initial release: Google sign-in, items and categories in Sheets, photos in Drive, gallery and list views.
