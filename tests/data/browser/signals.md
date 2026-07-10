# Browser Signal Reference Values

This file documents realistic browser signal values for different
browser/OS combinations. These are used for integration testing.

## Chrome 120 / Windows 10

| Signal | Value |
| -------- | ------- |
| navigator.cookieEnabled | true |
| navigator.userAgent | Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ... |
| navigator.language | en-US |
| navigator.languages | ["en-US", "en", "zh-CN"] |
| navigator.platform | Win32 |
| navigator.vendor | Google Inc. |
| navigator.hardwareConcurrency | 8 |
| navigator.deviceMemory | 8 |
| screen.width | 1920 |
| screen.height | 1080 |
| screen.colorDepth | 24 |

## Firefox 121 / macOS 14

| Signal | Value |
| -------- | ------- |
| navigator.cookieEnabled | true |
| navigator.userAgent | Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) ... |
| navigator.language | en-US |
| navigator.platform | MacIntel |
| navigator.vendor | (empty string) |
| navigator.hardwareConcurrency | 10 |
| navigator.deviceMemory | undefined (returns 0) |
| screen.width | 2560 |
| screen.height | 1600 |
| screen.devicePixelRatio | 2 |

## Safari 17 / iOS 17

| Signal | Value |
| -------- | ------- |
| navigator.cookieEnabled | true |
| navigator.userAgent | Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) ... |
| navigator.language | en-US |
| navigator.platform | iPhone |
| navigator.vendor | Apple Computer, Inc. |
| navigator.hardwareConcurrency | 6 |
| navigator.maxTouchPoints | 5 |
| screen.width | 390 |
| screen.height | 844 |
| screen.colorDepth | 32 |

## Edge 120 / Windows 11

| Signal | Value |
| -------- | ------- |
| navigator.cookieEnabled | true |
| navigator.userAgent | Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ... Edg/120.0.0.0 |
| navigator.platform | Win32 |
| navigator.vendor | Google Inc. |
| navigator.hardwareConcurrency | 16 |
| navigator.deviceMemory | 16 |
