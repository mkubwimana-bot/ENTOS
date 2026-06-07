# Offline and Mobile Notes

## MVP Principle

Support limited offline transaction drafts, not a full offline ERP.

## Mobile MVP Transactions

- Quick sale

- Customer payment

- Stock check

- Customer balance check

- Stock adjustment

## Offline Rules

- Offline transactions are drafts until synced.

- Server assigns final invoice/payment numbers.

- Use client_reference_id to prevent duplicates.

- Pending drafts must not be counted as posted sales.

- EBM and Mobile Money confirmations require internet.

## Key Tables

- mobile_devices

- device_sessions

- transaction_drafts

- sync_queue

- sync_logs

- conflict_logs

- offline_cache_metadata

- number_sequences