# Municipality cover suggestions

This authenticated Edge Function derives the municipality from the signed-in
subtenant's `subtenant_details` row. The client cannot supply another
municipality. Pexels credentials remain server-side.

Configure and deploy:

```powershell
npx supabase secrets set PEXELS_API_KEY="your-pexels-api-key" --project-ref mvtqhsrdgtwdeootgjci
npx supabase functions deploy municipality-cover-suggestions --project-ref mvtqhsrdgtwdeootgjci
```

The function returns an empty, non-fatal suggestion list when the key is not
configured. Local TourisTrike images and uploads do not depend on Pexels.
