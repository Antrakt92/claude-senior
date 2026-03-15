---
name: new-provider-checklist
description: Price provider implementation guide with error handling rules. Read when adding a new price data source.
type: project
summary: "10 steps: create provider, register in price_service, add throttling/DB columns/migration, update frontend types. CRITICAL error rules: never swallow RateLimitError in except Exception, never cache price=0 (poisons DB 24h for all users), distinguish transient (rate limit/network) from permanent (no data) failures."
---

# New Price Provider Checklist

## Backend

### 1. Create provider: `backend/app/services/providers/{provider_name}.py`
- Inherit from `PriceProvider` (base.py)
- Implement `name` property (lowercase: "coingecko", "yfinance")
- Implement `supported_asset_types` property (["crypto"], ["stock"], ["etf"], or combo)
- Implement async `get_price(symbol, price_date, currency)` -> Optional[PriceResult]
- Use `httpx.AsyncClient` for HTTP calls (never synchronous)

### 2. Export: `backend/app/services/providers/__init__.py`
- Import class, add to `__all__`

### 3. Register: `backend/app/services/price_service.py`
- Add to `self._crypto_providers` / `self._stock_providers` / `self._etf_providers`
- Order matters — primary providers first (fallback order)

### 4. Throttling: `backend/app/services/api_usage_tracker.py`
- Add to `PROVIDER_THROTTLE_SECONDS` (safe minimum delay in seconds)
- Add to `PROVIDER_COLUMN_MAP` ("{provider}_calls" -> DB column)
- Add to `PROVIDER_DAILY_WARNING_THRESHOLDS` (daily call limit warning)

### 5. DB columns: `backend/app/models/entities.py`
- Add `{provider_name}_calls: int` column to `ApiUsageDaily` table

### 6. Migration: `backend/alembic/versions/`
- `cd backend && alembic revision --autogenerate -m "Add {provider} call tracking"`
- `cd backend && alembic upgrade head`

## Frontend

### 7. Health display: `frontend/src/components/settings/AccountTab.tsx`
- Provider health auto-populates from backend — may need type updates

### 8. Types: `frontend/src/services/authApi.ts`
- Update `ProviderHealthResult` type if custom health checks needed

## Tests

### 9. Provider tests: `backend/tests/test_price_service.py`
- Test `name` and `supported_asset_types` properties
- Test success case (valid price returned)
- Test rate limit (RateLimitError raised)
- Test provider error (ProviderError raised)
- Test symbol not found (None returned)
- Test FX conversion

### 10. Integration: `backend/tests/test_fill_crypto_prices.py`
- Test new provider is called for price filling
- Test fallback to secondary provider on failure

## Error Handling (CRITICAL)

### ALWAYS DO:
- `except RateLimitError: raise` BEFORE any `except Exception` block
- Raise `RateLimitError(message, retry_after=seconds)` for 429/503
- Wrap `httpx.HTTPStatusError` as `ProviderError` for 4xx (permanent)
- Wrap `httpx.RequestError` as `ProviderError` for timeouts/connection
- Return `None` only when symbol doesn't exist (permanent, OK to cache)

### NEVER DO:
- Swallow `RateLimitError` in generic `except Exception`
- Cache `price=0` or negative prices from transient failures (poisons DB cache 24h for ALL users)
- Cache rate limit errors in DB
- Use synchronous HTTP calls

## Provider Structure Template

```python
class MyProvider(PriceProvider):
    @property
    def name(self) -> str:
        return "myprovider"

    @property
    def supported_asset_types(self) -> list[str]:
        return ["crypto"]

    async def get_price(self, symbol, price_date, currency="EUR"):
        try:
            # 1. Validate date (no future prices)
            # 2. Fetch from API via httpx.AsyncClient
            # 3. Return PriceResult(price, currency, source)
            pass
        except RateLimitError:
            raise  # MUST re-raise before any except Exception
        except httpx.HTTPStatusError as e:
            raise ProviderError(str(e)) from e
        except httpx.RequestError as e:
            raise ProviderError(str(e)) from e
```

## Symbol Mapping (if needed)
- Crypto providers often need ticker -> provider ID mapping
- Example: CoinGecko maps BTC -> "bitcoin", ETH -> "ethereum"
- Falls back to search endpoint for unknown symbols
