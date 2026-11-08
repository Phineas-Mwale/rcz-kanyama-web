# RCZ Kanyama

The official congregation app for RCZ Kanyama, built with Flutter. It includes
member registration, hymns, sermons, notices, and a Secretariat dashboard backed
by Supabase. 

## Run locally

```text
flutter pub get
flutter run -d chrome
```

## Build the web version

```text
flutter build web --release
```

The deployable files are generated in `build/web`.

## Supabase setup

Follow [`supabase/SETUP.md`](supabase/SETUP.md) to create the database schema,
storage bucket, and YouTube sync function. The app uses only the Supabase project
URL and publishable key in [`lib/supabase_config.dart`](lib/supabase_config.dart).
Never put a Supabase service-role key in the app or repository.

## Deploy to Vercel

This repository includes [`vercel.json`](vercel.json), which serves the committed
Flutter web build as a single-page application. After rebuilding, commit the
updated `build/web` directory and push it to GitHub; Vercel will redeploy it
automatically. 
