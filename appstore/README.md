# App Store metadata

Store text for GeoNap, uploaded to App Store Connect by `upload_metadata.py`
(App Store Connect API). Folder names are App Store Connect locale codes.

    metadata/<locale>/keywords.txt          max 100 chars, comma-separated, no spaces after commas
    metadata/<locale>/whats_new.txt         release notes for this version
    metadata/<locale>/description.txt       optional — only uploaded where the file exists
    metadata/<locale>/promotional_text.txt  optional, max 170 (changeable without review)
    metadata/<locale>/support_url.txt       support page URL
    metadata/<locale>/subtitle.txt          optional, max 30 (App Information)
    metadata/<locale>/name.txt              optional, max 30 (App Information; new languages
                                            copy the primary language's name if missing)
    metadata/<locale>/privacy_policy_url.txt optional (new languages copy the primary's if missing)

To add languages that aren't on the listing yet, add --create-missing. A new language
needs description, keywords and support_url; nothing is written if any is missing.

Run (dry run first, then --apply):

    python3 appstore/upload_metadata.py --version 1.1.0
    python3 appstore/upload_metadata.py --version 1.1.0 --apply

Setup and API key instructions are at the top of `upload_metadata.py`.
Changes under appstore/ do not trigger CI (paths-ignore in .github/workflows/gtfs-tests.yml).
