## 1. Compression Levels (Static Mapping)

No real “calculation” happens here—each file extension is simply assigned a 7z compression level, `-mx=N`.  The higher the `N`, the more aggressive (and slower) the compression.  Per **math.md**:

| Extension(s)   | `-mx` Level | Description   |
|---------------:|------------:|---------------|
| `flac`, `wav`  | 9           | maximum       |
| `ogg`, `opus`  | 7           | high          |
| `aac`          | 6           | medium-high   |
| `mp3`          | 5           | medium        |
| `mp4`, `mov`   | 4           | medium-low    |
| _other_        | 9           | default (max) |

> _No other numeric math is performed during compression; decompression has no tunable parameters._ 

In code this is simply a `case "$ext" in … echo "-mx=9" … esac` lookup in `get_compression_settings()`.

---

## 2. Scan-Threshold Calculation (Heuristic)

When you run `--scan`, **mm.sh** does the following for each media file:

1. **Extract metadata** via `ffprobe`:  
   - **Duration** in seconds (`duration`)  
   - **Bitrate** in bits-per-second (`bitrate`)  

2. **Compute the “expected” filesize** in bytes:  
   ```bash
   expected_bytes = (duration_seconds × bitrate_bps) / 8
   ```
   - We divide by 8 because bitrate is in _bits_ per second, but filesize is measured in _bytes_.  

3. **Apply a tolerance threshold** of 1.5× to catch anomalously large files:  
   ```bash
   threshold_bytes = expected_bytes × 1.5
   ```

4. **Compare** the actual filesize (`stat -c%s`) against this threshold:  
   - If `filesize > threshold_bytes`, classify as **“weird”**  
   - Otherwise, classify as **“normal”**  
   - If `ffprobe` itself fails, classify as **“corrupted”**

All of this is done with **bc** for floating-point precision (scale=2):

```bash
# inside scan_media()
expected_bytes=$(echo "scale=2; ($duration * $bitrate) / 8" | bc -l)
threshold_bytes=$(echo "scale=2; $expected_bytes * 1.5" | bc -l)
is_weird=$(echo "$filesize > $threshold_bytes" | bc -l)
```

—so you end up with a two-decimal “expected” size, a 1.5× margin, and a simple greater-than test .

---

### Why this math?

- **Division by 8** converts from bits to bytes.  
- **Multiplying by 1.5** gives a 50% headroom to account for variable encoding overhead (e.g., metadata, padding).  
- **Floating-point via `bc -l`** ensures precise thresholds with two-decimal accuracy (`scale=2`).  

Together, this heuristic flags files whose actual size is significantly larger than what their duration × bitrate would predict—catching things like excessive padding, hidden streams, or outright corruption.

---

With these two sections—the static compression-level table and the scan-threshold math—you’ve captured all of the quantitative logic in **mm.sh**.
