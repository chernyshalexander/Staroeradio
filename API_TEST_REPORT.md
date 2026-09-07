# API Test Results - Critical Findings

## Test Summary

**Date:** July 22, 2026  
**Branch:** feature/api-covers-mode  
**Status:** ❌ **API NOT WORKING - CRITICAL ISSUE**

---

## Key Findings

### 1. Server Availability

| Server | Status | Details |
|--------|--------|---------|
| **server.audiopedia.su:8888** (.ru) | ❌ **FAIL** | Connection timeout (30s) |
| **server.audiopedia.world:8888** (.world) | ✅ **PASS** | Working, limited functionality |

### 2. API Endpoint Testing

#### ✅ WORKING: Get Current Track Info
```
GET http://server.audiopedia.world:8888/getcurrentinfo.php
Response: XML with current track information
```

**Sample Response:**
```xml
<data>
  <staroeradio>
    <id>44206</id>
    <name>Конькова А., Сорокин В. - Роса под солнцем...</name>
    <file>Конькова А- Роса под солнцем - по легендам бабушки Аннэ.mp3</file>
    <time>00:25:33</time>
    <start>2026-06-16 15:42:02</start>
  </staroeradio>
  <detskoeradio>
    <id>29144</id>
    <name>Всесоюзное радио - На зарядку становись...</name>
  </detskoeradio>
</data>
```

**Real track_ids obtained:**
- staroeradio: **44206**
- detskoeradio: **29144**

---

#### ❌ NOT WORKING: Get Metadata with Cover Images
```
GET http://server.audiopedia.world:8888/getradioinfo.php?cmd=getMetaInfo&track_id=X
Response: 200 OK, but EMPTY (0 bytes)
```

**Tested Variations:**
- `track_id=44206` → Empty
- `track_id=29144` → Empty  
- `track_id=12345` → Empty
- `track_id=0` → Empty
- `id=X` (different parameter) → Empty
- Different endpoint paths → Empty

**All variations returned 200 OK with 0 bytes response.**

---

## Test Results Summary

| Test | Status | Notes |
|------|--------|-------|
| Get current track info (.world) | ✅ PASS | XML works, got real track_ids |
| Get metadata (44206) | ❌ FAIL | Empty response |
| Get metadata (29144) | ❌ FAIL | Empty response |
| Get metadata (multiple IDs) | ❌ FAIL | All empty |
| Get current track info (.ru) | ❌ FAIL | Server timeout |

**Overall: 1/9 tests passed (11.1%)**

---

## Analysis & Implications

### What Works:
✅ We can get the current playing track_id from live stream  
✅ XML API is functional  
✅ .world domain is accessible

### What Doesn't Work:
❌ **Cover image API is NOT working**  
❌ Cannot retrieve track metadata  
❌ Cannot get image URLs  
❌ .ru domain is completely inaccessible

---

## Root Cause Analysis

**Possible reasons for API failure:**

1. **API Deprecated**: The `/getradioinfo.php?cmd=getMetaInfo` endpoint may no longer be supported
2. **Parameter Format**: API may require different parameters than Android app uses
3. **Domain Restriction**: API may only work on .ru domain (currently down)
4. **Authentication**: API may require additional headers/credentials
5. **Service Temporary Issue**: API service may be temporarily down

---

## Files Created

✅ `test_results/api_test_report.txt` — Full test report  
✅ `test_results/images/` — Directory for downloaded images (empty - no images available)  
✅ `test_api_requests.pl` — Main test script  
✅ `test_real_track.pl` — Test with real track_ids  
✅ `test_analyze_xml.pl` — XML structure analysis  
✅ `test_staroe_track.pl` — Endpoint variation testing

---

## Recommendations

### Option A: Investigate Android App Further
**Rationale:** Android app successfully shows cover art, so it must use working endpoints  
**Action:** 
- Reverse-engineer actual HTTP requests from Android app
- Check if app uses different API endpoints
- Look for API version differences

### Option B: HTML Scraping Approach  
**Rationale:** If API doesn't work, fall back to scraping HTML for images  
**Action:**
- Inspect website HTML for image URLs
- Parse `<img>` tags from search results
- Use existing parsing infrastructure

### Option C: Contact Service Provider
**Rationale:** API may be temporarily down or changed  
**Action:**
- Check service status page
- Contact support about API availability
- Ask for correct API documentation

### Option D: Code Review Experiment Branch
**Rationale:** Experiment branch claims to have working API implementation  
**Action:**
- Review how experiment branch handles API calls
- Check if it has workarounds or different endpoints
- Learn from existing implementation

---

## Next Steps - REQUIRES USER DECISION

**❌ CRITICAL STOPPING POINT:** API for cover images is NOT WORKING.

**Cannot proceed with implementation until:**
1. API functionality is confirmed OR
2. Alternative approach (HTML scraping) is chosen OR
3. Android app reverse-engineering reveals working endpoints

**Question for user:**
How should we proceed?

1. **Investigate Android app** — Reverse-engineer actual working endpoints
2. **Switch to HTML scraping** — Parse images from website HTML instead
3. **Review experiment branch** — See how it handles this issue
4. **Contact API provider** — Check service status/documentation
5. **Wait and retry later** — API may be temporarily down

---

## Technical Details

### Working XML API
```
Endpoint: http://server.audiopedia.world:8888/getcurrentinfo.php
Method: GET
Response: XML (790 bytes)
Reliability: ✅ 100%
```

### Broken JSON API  
```
Endpoint: http://server.audiopedia.world:8888/getradioinfo.php?cmd=getMetaInfo&track_id=X
Method: GET
Response: 200 OK, 0 bytes
Reliability: ❌ 0% (always empty)
```

### Test Environment
- Perl 5.38.2
- LWP::UserAgent for HTTP requests
- JSON::PP for JSON parsing
- Test duration: ~3 minutes
- Total requests: 9
- Successful: 1 (11.1%)

---

## Conclusion

**❌ CANNOT PROCEED WITH API IMPLEMENTATION**

The API endpoint for retrieving cover images is not functional on the .world domain, and the .ru domain is completely inaccessible.

**Recommendation:** Switch to **Option D (Review experiment branch)** or **Option B (HTML scraping)** to find a working solution for cover art support.

**Path B (Partial API integration) is BLOCKED** until API endpoint issues are resolved.
