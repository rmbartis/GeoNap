# App Store metadata

Store text for GeoNap, uploaded to App Store Connect by `upload_metadata.py`
(App Store Connect API). Folder names are App Store Connect locale codes.

    metadata/<locale>/keywords.txt          max 100 chars, comma-separated, no spaces after commas
    metadata/<locale>/whats_new.txt         release notes for this version
    metadata/<locale>/description.txt       optional — only uploaded where the file exists
    metadata/<locale>/promotional_text.txt  optional, max 170 (changeable without review)
    metadata/<locale>/subtitle.txt          optional, max 30

Run (dry run first, then --apply):

    python3 appstore/upload_metadata.py --version 1.1.0
    python3 appstore/upload_metadata.py --version 1.1.0 --apply

Setup and API key instructions are at the top of `upload_metadata.py`.
Changes under appstore/ do not trigger CI (paths-ignore in .github/workflows/gtfs-tests.yml).
