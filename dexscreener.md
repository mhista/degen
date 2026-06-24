# DEX Screener API Reference

**Base URL:** `https://api.dexscreener.com`  
**Version:** 1.0.0  
**Default rate limit:** 60 requests per minute (all endpoints)

---

## Shared Schemas

### TokenProfile

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `url` | `string (uri)` | No | |
| `chainId` | `string` | No | |
| `tokenAddress` | `string` | No | |
| `icon` | `string (uri)` | No | |
| `header` | `string (uri)` | Yes | |
| `description` | `string` | Yes | |
| `links` | `array[Link]` | Yes | |

**Link object:**

| Field | Type | Nullable |
|---|---|---|
| `type` | `string` | Yes |
| `label` | `string` | Yes |
| `url` | `string (uri)` | No |

---

### Pair

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `chainId` | `string` | No | |
| `dexId` | `string` | No | |
| `url` | `string (uri)` | No | |
| `pairAddress` | `string` | No | |
| `labels` | `array[string]` | Yes | |
| `baseToken` | `Token` | No | |
| `quoteToken` | `Token` | Yes | fields nullable |
| `priceNative` | `string` | No | |
| `priceUsd` | `string` | Yes | |
| `txns` | `map<string, TxnStats>` | No | keyed by timeframe: `m5`, `h1`, `h6`, `h24` |
| `volume` | `map<string, number>` | No | keyed by timeframe |
| `priceChange` | `map<string, number>` | Yes | keyed by timeframe |
| `liquidity` | `Liquidity` | Yes | |
| `fdv` | `number` | Yes | |
| `marketCap` | `number` | Yes | |
| `pairCreatedAt` | `integer` | Yes | Unix timestamp (ms) |
| `info` | `PairInfo` | No | |
| `boosts` | `{ active: integer }` | No | |

**Token object:**

| Field | Type | Nullable |
|---|---|---|
| `address` | `string` | No |
| `name` | `string` | No |
| `symbol` | `string` | No |

**TxnStats object:**

| Field | Type |
|---|---|
| `buys` | `integer` |
| `sells` | `integer` |

**Liquidity object:**

| Field | Type | Nullable |
|---|---|---|
| `usd` | `number` | Yes |
| `base` | `number` | No |
| `quote` | `number` | No |

**PairInfo object:**

| Field | Type | Nullable |
|---|---|---|
| `imageUrl` | `string (uri)` | Yes |
| `websites` | `array[{ url: string }]` | Yes |
| `socials` | `array[{ platform: string, handle: string }]` | Yes |

---

### Meta

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `name` | `string` | No | |
| `slug` | `string` | No | |
| `description` | `string` | No | |
| `icon` | `{ type: string, value: string }` | No | |
| `marketCap` | `number (double)` | No | |
| `liquidity` | `number (double)` | No | |
| `volume` | `number (double)` | No | |
| `tokenCount` | `integer` | No | |
| `marketCapChange` | `TimeframeStats` | No | |
| `marketCapDelta` | `TimeframeStats` | No | |

**TimeframeStats object** (all fields required):

| Field | Type |
|---|---|
| `m5` | `number (double)` |
| `h1` | `number (double)` |
| `h6` | `number (double)` |
| `h24` | `number (double)` |

---

## Endpoints

---

### Token Profiles

#### GET `/token-profiles/latest/v1`

Get the latest token profiles.

**Response `200`:** `TokenProfile`

```json
{
  "url": "https://dexscreener.com/solana/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  "chainId": "solana",
  "tokenAddress": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  "icon": "https://dd.dexscreener.com/ds-data/tokens/solana/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v.png",
  "header": "https://dd.dexscreener.com/ds-data/tokens/solana/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/header.png",
  "description": "USD Coin (USDC) is a fully collateralized US dollar stablecoin.",
  "links": [
    {
      "type": "twitter",
      "label": "Twitter",
      "url": "https://twitter.com/circle"
    },
    {
      "type": "website",
      "label": "Website",
      "url": "https://www.circle.com/usdc"
    }
  ]
}
```

---

#### GET `/token-profiles/recent-updates/v1`

Get recently updated token profiles.

**Response `200`:** `TokenProfile`

```json
{
  "url": "https://dexscreener.com/ethereum/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
  "chainId": "ethereum",
  "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
  "icon": "https://dd.dexscreener.com/ds-data/tokens/ethereum/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.png",
  "header": null,
  "description": null,
  "links": null
}
```

---

### Community Takeovers

#### GET `/community-takeovers/latest/v1`

Get the latest token community takeovers.

**Response `200`:** `array[CommunityTakeover]`

**CommunityTakeover** extends `TokenProfile` with:

| Field | Type | Nullable |
|---|---|---|
| `claimDate` | `string (date-time)` | No |

```json
[
  {
    "url": "https://dexscreener.com/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "chainId": "solana",
    "tokenAddress": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "icon": "https://dd.dexscreener.com/ds-data/tokens/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263.png",
    "header": "https://dd.dexscreener.com/ds-data/tokens/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263/header.png",
    "description": "Bonk is the first Solana dog coin for the people.",
    "links": [
      {
        "type": "twitter",
        "label": "Twitter",
        "url": "https://twitter.com/bonk_inu"
      }
    ],
    "claimDate": "2024-11-15T08:30:00.000Z"
  }
]
```

---

### Ads

#### GET `/ads/latest/v1`

Get the latest ads.

**Response `200`:** `array[Ad]`

**Ad object:**

| Field | Type | Nullable |
|---|---|---|
| `url` | `string (uri)` | No |
| `chainId` | `string` | No |
| `tokenAddress` | `string` | No |
| `date` | `string (date-time)` | No |
| `type` | `string` | No |
| `durationHours` | `number` | Yes |
| `impressions` | `number` | Yes |

```json
[
  {
    "url": "https://dexscreener.com/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "chainId": "solana",
    "tokenAddress": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "date": "2024-11-15T08:00:00.000Z",
    "type": "banner",
    "durationHours": 24,
    "impressions": 15200
  }
]
```

---

### Token Boosts

#### GET `/token-boosts/latest/v1`

Get the latest boosted tokens.

**Response `200`:** `array[TokenBoost]`

**TokenBoost object:**

| Field | Type | Nullable |
|---|---|---|
| `url` | `string (uri)` | No |
| `chainId` | `string` | No |
| `tokenAddress` | `string` | No |
| `icon` | `string (uri)` | Yes |
| `header` | `string (uri)` | Yes |
| `description` | `string` | Yes |
| `links` | `array[Link]` | Yes |
| `amount` | `number` | No |
| `totalAmount` | `number` | No |

```json
[
  {
    "url": "https://dexscreener.com/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "chainId": "solana",
    "tokenAddress": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "icon": "https://dd.dexscreener.com/ds-data/tokens/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263.png",
    "header": null,
    "description": "Bonk is the first Solana dog coin for the people.",
    "links": [
      {
        "type": "twitter",
        "label": "Twitter",
        "url": "https://twitter.com/bonk_inu"
      }
    ],
    "amount": 500,
    "totalAmount": 1500
  }
]
```

---

#### GET `/token-boosts/top/v1`

Get the tokens with the most active boosts.

**Response `200`:** `array[TokenBoost]` (same schema as above)

```json
[
  {
    "url": "https://dexscreener.com/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "chainId": "solana",
    "tokenAddress": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    "icon": "https://dd.dexscreener.com/ds-data/tokens/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263.png",
    "header": null,
    "description": "Bonk is the first Solana dog coin for the people.",
    "links": null,
    "amount": 2000,
    "totalAmount": 8500
  }
]
```

---

### Orders

#### GET `/orders/v1/{chainId}/{tokenAddress}`

Check orders paid for a token.

**Path parameters:**

| Parameter | Type | Required |
|---|---|---|
| `chainId` | `string` | Yes |
| `tokenAddress` | `string` | Yes |

**Response `200`:** `array[Order]`

**Order object:**

| Field | Type | Nullable |
|---|---|---|
| `type` | `string` | No |
| `status` | `string` | No |
| `paymentTimestamp` | `integer` | No |

```json
[
  {
    "type": "tokenProfile",
    "status": "approved",
    "paymentTimestamp": 1731657600000
  },
  {
    "type": "communityTakeover",
    "status": "processing",
    "paymentTimestamp": 1731744000000
  }
]
```

---

### Pairs

#### GET `/latest/dex/pairs/{chainId}/{pairId}`

Get one or multiple pairs by chain and pair address. `pairId` accepts a comma-separated list of up to 30 pair addresses.

**Path parameters:**

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `chainId` | `string` | Yes | e.g. `solana`, `ethereum`, `bsc` |
| `pairId` | `string` | Yes | Comma-separated pair addresses (up to 30) |

**Response `200`:**

| Field | Type |
|---|---|
| `schemaVersion` | `string` |
| `pairs` | `array[Pair]` |

```json
{
  "schemaVersion": "1.0.0",
  "pairs": [
    {
      "chainId": "solana",
      "dexId": "raydium",
      "url": "https://dexscreener.com/solana/7XawhbbxtsRcQA8KTkHT9f9nc6d69UwqCDh6U5EEbEmX",
      "pairAddress": "7XawhbbxtsRcQA8KTkHT9f9nc6d69UwqCDh6U5EEbEmX",
      "labels": ["v2"],
      "baseToken": {
        "address": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
        "name": "Bonk",
        "symbol": "BONK"
      },
      "quoteToken": {
        "address": "So11111111111111111111111111111111111111112",
        "name": "Wrapped SOL",
        "symbol": "SOL"
      },
      "priceNative": "0.000000014523",
      "priceUsd": "0.000002187",
      "txns": {
        "m5":  { "buys": 12, "sells": 8 },
        "h1":  { "buys": 145, "sells": 98 },
        "h6":  { "buys": 872, "sells": 654 },
        "h24": { "buys": 3201, "sells": 2489 }
      },
      "volume": {
        "m5": 1820.45,
        "h1": 24510.80,
        "h6": 148320.50,
        "h24": 612480.90
      },
      "priceChange": {
        "m5": 0.12,
        "h1": -1.45,
        "h6": 3.82,
        "h24": -8.21
      },
      "liquidity": {
        "usd": 1240500.75,
        "base": 567800000000,
        "quote": 8745.32
      },
      "fdv": 1384200,
      "marketCap": 1102400,
      "pairCreatedAt": 1672531200000,
      "info": {
        "imageUrl": "https://dd.dexscreener.com/ds-data/tokens/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263.png",
        "websites": [
          { "url": "https://bonkcoin.com" }
        ],
        "socials": [
          { "platform": "twitter", "handle": "bonk_inu" },
          { "platform": "telegram", "handle": "bonk_inu" }
        ]
      },
      "boosts": {
        "active": 3
      }
    }
  ]
}
```

---

#### GET `/latest/dex/search`

Search for pairs matching a query string (token name, symbol, or address).

**Query parameters:**

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `q` | `string` | Yes | Token name, symbol, or address |

**Response `200`:**

| Field | Type |
|---|---|
| `schemaVersion` | `string` |
| `pairs` | `array[Pair]` |

```json
{
  "schemaVersion": "1.0.0",
  "pairs": [
    {
      "chainId": "ethereum",
      "dexId": "uniswap",
      "url": "https://dexscreener.com/ethereum/0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
      "pairAddress": "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
      "labels": ["v3"],
      "baseToken": {
        "address": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "name": "USD Coin",
        "symbol": "USDC"
      },
      "quoteToken": {
        "address": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
        "name": "Wrapped Ether",
        "symbol": "WETH"
      },
      "priceNative": "0.0003321",
      "priceUsd": "1.0002",
      "txns": {
        "m5":  { "buys": 45, "sells": 38 },
        "h1":  { "buys": 512, "sells": 489 },
        "h6":  { "buys": 3120, "sells": 2980 },
        "h24": { "buys": 12400, "sells": 11850 }
      },
      "volume": {
        "m5": 480200.10,
        "h1": 5820400.50,
        "h6": 34900800.25,
        "h24": 139600000.00
      },
      "priceChange": {
        "m5": 0.01,
        "h1": -0.02,
        "h6": 0.00,
        "h24": 0.03
      },
      "liquidity": {
        "usd": 185400000.00,
        "base": 92700000,
        "quote": 30850.45
      },
      "fdv": null,
      "marketCap": null,
      "pairCreatedAt": 1620000000000,
      "info": {
        "imageUrl": "https://dd.dexscreener.com/ds-data/tokens/ethereum/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.png",
        "websites": [
          { "url": "https://www.circle.com/usdc" }
        ],
        "socials": [
          { "platform": "twitter", "handle": "circle" }
        ]
      },
      "boosts": {
        "active": 0
      }
    }
  ]
}
```

---

### Token Pairs

#### GET `/token-pairs/v1/{chainId}/{tokenAddress}`

Get all pools/pairs for a given token address.

**Path parameters:**

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `chainId` | `string` | Yes | e.g. `solana`, `ethereum` |
| `tokenAddress` | `string` | Yes | Token contract address |

**Response `200`:** `array[Pair]`

```json
[
  {
    "chainId": "solana",
    "dexId": "raydium",
    "url": "https://dexscreener.com/solana/7XawhbbxtsRcQA8KTkHT9f9nc6d69UwqCDh6U5EEbEmX",
    "pairAddress": "7XawhbbxtsRcQA8KTkHT9f9nc6d69UwqCDh6U5EEbEmX",
    "labels": ["v2"],
    "baseToken": {
      "address": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
      "name": "Bonk",
      "symbol": "BONK"
    },
    "quoteToken": {
      "address": "So11111111111111111111111111111111111111112",
      "name": "Wrapped SOL",
      "symbol": "SOL"
    },
    "priceNative": "0.000000014523",
    "priceUsd": "0.000002187",
    "txns": {
      "m5":  { "buys": 12, "sells": 8 },
      "h1":  { "buys": 145, "sells": 98 },
      "h6":  { "buys": 872, "sells": 654 },
      "h24": { "buys": 3201, "sells": 2489 }
    },
    "volume": {
      "m5": 1820.45,
      "h1": 24510.80,
      "h6": 148320.50,
      "h24": 612480.90
    },
    "priceChange": {
      "m5": 0.12,
      "h1": -1.45,
      "h6": 3.82,
      "h24": -8.21
    },
    "liquidity": {
      "usd": 1240500.75,
      "base": 567800000000,
      "quote": 8745.32
    },
    "fdv": 1384200,
    "marketCap": 1102400,
    "pairCreatedAt": 1672531200000,
    "info": {
      "imageUrl": "https://dd.dexscreener.com/ds-data/tokens/solana/DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263.png",
      "websites": [
        { "url": "https://bonkcoin.com" }
      ],
      "socials": [
        { "platform": "twitter", "handle": "bonk_inu" }
      ]
    },
    "boosts": {
      "active": 3
    }
  }
]
```

---

### Tokens

#### GET `/tokens/v1/{chainId}/{tokenAddresses}`

Get one or multiple tokens by address. Returns the trading pairs associated with each token.

**Path parameters:**

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `chainId` | `string` | Yes | e.g. `solana`, `ethereum` |
| `tokenAddresses` | `string` | Yes | Comma-separated addresses (up to 30) |

**Response `200`:** `array[Pair]`

```json
[
  {
    "chainId": "ethereum",
    "dexId": "uniswap",
    "url": "https://dexscreener.com/ethereum/0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
    "pairAddress": "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
    "labels": ["v3"],
    "baseToken": {
      "address": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      "name": "USD Coin",
      "symbol": "USDC"
    },
    "quoteToken": {
      "address": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      "name": "Wrapped Ether",
      "symbol": "WETH"
    },
    "priceNative": "0.0003321",
    "priceUsd": "1.0002",
    "txns": {
      "m5":  { "buys": 45, "sells": 38 },
      "h1":  { "buys": 512, "sells": 489 },
      "h6":  { "buys": 3120, "sells": 2980 },
      "h24": { "buys": 12400, "sells": 11850 }
    },
    "volume": {
      "m5": 480200.10,
      "h1": 5820400.50,
      "h6": 34900800.25,
      "h24": 139600000.00
    },
    "priceChange": {
      "m5": 0.01,
      "h1": -0.02,
      "h6": 0.00,
      "h24": 0.03
    },
    "liquidity": {
      "usd": 185400000.00,
      "base": 92700000,
      "quote": 30850.45
    },
    "fdv": null,
    "marketCap": null,
    "pairCreatedAt": 1620000000000,
    "info": {
      "imageUrl": "https://dd.dexscreener.com/ds-data/tokens/ethereum/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.png",
      "websites": [
        { "url": "https://www.circle.com/usdc" }
      ],
      "socials": [
        { "platform": "twitter", "handle": "circle" }
      ]
    },
    "boosts": {
      "active": 0
    }
  }
]
```

---

### Metas

#### GET `/metas/trending/v1`

Get trending metas (narrative categories grouping related tokens).

**Response `200`:** `array[Meta]`

```json
[
  {
    "name": "AI Agents",
    "slug": "ai-agents",
    "description": "Tokens associated with autonomous AI agent projects.",
    "icon": {
      "type": "emoji",
      "value": "🤖"
    },
    "marketCap": 4820000000.00,
    "liquidity": 312000000.00,
    "volume": 980000000.00,
    "tokenCount": 84,
    "marketCapChange": {
      "m5": 0.12,
      "h1": 1.45,
      "h6": -2.30,
      "h24": 8.75
    },
    "marketCapDelta": {
      "m5": 5784000.00,
      "h1": 69890000.00,
      "h6": -110860000.00,
      "h24": 421750000.00
    }
  },
  {
    "name": "Memecoins",
    "slug": "memecoins",
    "description": "Community-driven meme tokens.",
    "icon": {
      "type": "emoji",
      "value": "🐶"
    },
    "marketCap": 62100000000.00,
    "liquidity": 1840000000.00,
    "volume": 5200000000.00,
    "tokenCount": 412,
    "marketCapChange": {
      "m5": -0.05,
      "h1": -0.82,
      "h6": 1.20,
      "h24": -4.10
    },
    "marketCapDelta": {
      "m5": -31050000.00,
      "h1": -509220000.00,
      "h6": 745200000.00,
      "h24": -2546100000.00
    }
  }
]
```

---

#### GET `/metas/meta/v1/{slug}`

Get full meta information including all associated trading pairs for a given slug.

**Path parameters:**

| Parameter | Type | Required |
|---|---|---|
| `slug` | `string` | Yes |

**Response `200`:** `Meta` extended with a `pairs` array

| Field | Type |
|---|---|
| `pairs` | `array[Pair]` |

```json
{
  "name": "AI Agents",
  "slug": "ai-agents",
  "description": "Tokens associated with autonomous AI agent projects.",
  "icon": {
    "type": "emoji",
    "value": "🤖"
  },
  "marketCap": 4820000000.00,
  "liquidity": 312000000.00,
  "volume": 980000000.00,
  "tokenCount": 84,
  "marketCapChange": {
    "m5": 0.12,
    "h1": 1.45,
    "h6": -2.30,
    "h24": 8.75
  },
  "marketCapDelta": {
    "m5": 5784000.00,
    "h1": 69890000.00,
    "h6": -110860000.00,
    "h24": 421750000.00
  },
  "pairs": [
    {
      "chainId": "solana",
      "dexId": "raydium",
      "url": "https://dexscreener.com/solana/4k3Dyjzvzp8e6bCkPKMw9oFcGfNGCVUfkGSRm5V8nCr7",
      "pairAddress": "4k3Dyjzvzp8e6bCkPKMw9oFcGfNGCVUfkGSRm5V8nCr7",
      "labels": ["v4"],
      "baseToken": {
        "address": "AIagent1111111111111111111111111111111111111",
        "name": "AI Agent Token",
        "symbol": "AIT"
      },
      "quoteToken": {
        "address": "So11111111111111111111111111111111111111112",
        "name": "Wrapped SOL",
        "symbol": "SOL"
      },
      "priceNative": "0.00425",
      "priceUsd": "0.6391",
      "txns": {
        "m5":  { "buys": 22, "sells": 15 },
        "h1":  { "buys": 280, "sells": 195 },
        "h6":  { "buys": 1640, "sells": 1120 },
        "h24": { "buys": 6200, "sells": 4380 }
      },
      "volume": {
        "m5": 8420.00,
        "h1": 104500.00,
        "h6": 621000.00,
        "h24": 2480000.00
      },
      "priceChange": {
        "m5": 0.45,
        "h1": 2.10,
        "h6": -1.80,
        "h24": 12.40
      },
      "liquidity": {
        "usd": 3820000.00,
        "base": 5978000,
        "quote": 12480.50
      },
      "fdv": 63910000,
      "marketCap": 51200000,
      "pairCreatedAt": 1700000000000,
      "info": {
        "imageUrl": "https://dd.dexscreener.com/ds-data/tokens/solana/AIagent1111111111111111111111111111111111111.png",
        "websites": [
          { "url": "https://aiagenttoken.io" }
        ],
        "socials": [
          { "platform": "twitter", "handle": "aiagenttoken" },
          { "platform": "telegram", "handle": "aiagenttoken" }
        ]
      },
      "boosts": {
        "active": 1
      }
    }
  ]
}
```