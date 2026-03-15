---
name: new-parser-checklist
description: 14-file registration checklist for adding new broker parsers. Read when implementing a new broker.
type: project
summary: "10 steps across backend/frontend/tests. Key: content-based detection (not filename), PARSER_REGISTRY ordering (specific before generic), crypto needs stablecoin mapping + TRANSFER_IN/OUT, dedup keys use quantity when gross_amount=0, API vs CSV broker naming ({broker}_api vs {broker}_csv)."
---

# New Broker Parser Checklist

## Backend

### 1. Create parser: `backend/app/parsers/{broker}_parser.py`
- Inherit from `BrokerParser` (base.py)
- Implement `broker_name` property (lowercase, snake_case)
- Implement `can_parse(file_path, content_sample)` — content-based detection, NOT filename
- Implement `parse(file_path)` returning `ParsedReport`
- Set `ParsedReport.broker = "broker_key"` matching PARSER_REGISTRY key

### 2. Export: `backend/app/parsers/__init__.py`
- Import new parser class, add to `__all__`

### 3. Register: `backend/app/routers/upload.py`
- Add to `PARSER_REGISTRY` dict — **ordering matters**: specific parsers before generic
- Update `UNSUPPORTED_FORMAT_HINTS` if similar formats exist that users might confuse

### 4. Constants (if crypto): `backend/app/constants/crypto.py`
- Add stablecoins to `STABLECOIN_TO_FIAT` if needed
- Add fiat currencies to `FIAT_CURRENCIES` if non-standard

### 5. Models (if new income types): `backend/app/models/entities.py`
- `income_type` must match existing `IncomeType` values: interest, dividend, distribution, staking_reward, earn_reward, crypto_reward, learn_reward

## Frontend

### 6. Upload tab: `frontend/src/components/upload/UploadFileTab.tsx`
- Add broker name and supported file types to help text / supported brokers table

### 7. Landing page: `frontend/src/constants/landingData.ts`
- Add broker name to COMPARISON_DATA "Multi-Broker Import" feature list

### 8. Integration card (if API sync): `frontend/src/components/integrations/{Broker}IntegrationCard.tsx`
- Use existing BinanceIntegrationCard.tsx as template
- Export from `integrations/index.ts`
- Add to `ApiConnectionsTab.tsx`

## Tests

### 9. Parser tests: `backend/tests/test_{broker}_parser.py`
- 2-3 real file examples minimum
- Test `can_parse()` with real content samples
- Test `parse()` output fields
- Test edge cases (missing ISIN, invalid data)

### 10. Integration test: `backend/tests/test_api_integration.py`
- Test upload auto-detection with the new format

## Key Rules

### Auto-detection
- Content-based only (first 500-2000 bytes), never filename
- Check for broker-specific metadata/headers
- PARSER_REGISTRY order: specific before generic, Ghostfolio last

### ParsedReport required fields
- `client_id`, `period_start`, `period_end`, `currency`, `country`
- `accounting_method` = "fifo" always
- `broker` = PARSER_REGISTRY key
- `transactions`, `income_events`, `gains_losses` (empty lists OK)
- `warnings` (ParsedWarning[] for validation issues)

### Crypto-specific
- Stablecoin→fiat conversion for MIXED trades (BTC bought with USDT)
- Stablecoin-to-stablecoin swaps are TAXABLE — don't convert
- Crypto ISIN prefix: `CRYPTO_{SYMBOL}`
- Dedup keys: use quantity (not gross_amount) when `gross_amount=0`
- TRANSFER_IN/OUT must accompany BUY/SELL queries

### API broker naming
- CSV = `{broker}_csv`, API = `{broker}_api` — prevents dedup conflicts
