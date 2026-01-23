import os, json, boto3, gzip, io, logging, re
from datetime import datetime, timezone

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")
PROCESSED_BUCKET = os.getenv("PROCESSED_BUCKET", "")

def _read_s3_object(bucket, key):
    obj = s3.get_object(Bucket=bucket, Key=key)
    body = obj["Body"].read()
    if key.endswith(".gz"):
        with gzip.GzipFile(fileobj=io.BytesIO(body)) as gz:
            data = gz.read()
    else:
        data = body
    # Try UTF-8 first; fall back to latin-1 to avoid decode errors
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1", errors="ignore")

def _write_lines_json(bucket, key, records, raw_text=None):
    buf = io.BytesIO()
    if records:
        for r in records:
            if isinstance(r, dict):
                r.pop("debug", None)  # example transform
            buf.write((json.dumps(r, separators=(",", ":")) + "\n").encode("utf-8"))
    else:
        # Fallback: write something so we can observe data shape
        payload = {"_unparsed": True, "raw": (raw_text[:5000] if raw_text else "")}
        buf.write((json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8"))
    buf.seek(0)
    s3.put_object(Bucket=bucket, Key=key, Body=buf.getvalue())

def _derive_partitions(key):
    # Expect keys like: raw/year=YYYY/month=MM/day=DD/...
    try:
        suffix = key.split("raw/")[1]
        year_dir, month_dir, day_dir = suffix.split("/", 3)[:3]
    except Exception:
        now = datetime.now(timezone.utc)
        year_dir  = f"year={now.year:04d}"
        month_dir = f"month={now.month:02d}"
        day_dir   = f"day={now.day:02d}"
    return year_dir, month_dir, day_dir

def _robust_parse(text):
    """
    Accepts:
      - NDJSON (one JSON per line)
      - Concatenated objects without newline: ...}{...
      - Whole payload as a JSON object or array
    Skips non-JSON noise lines.
    """
    recs = []

    # 1) Try NDJSON lines
    for raw in text.splitlines():
        line = raw.strip()
        if not line or not (line.startswith("{") or line.startswith("[")):
            continue
        try:
            obj = json.loads(line)
            if isinstance(obj, list):
                recs.extend(obj)
            else:
                recs.append(obj)
        except json.JSONDecodeError:
            continue
    if recs:
        return recs

    # 2) Try whole payload as JSON (array or object)
    stripped = text.strip()
    if stripped:
        try:
            obj = json.loads(stripped)
            if isinstance(obj, list):
                return obj
            elif isinstance(obj, dict):
                return [obj]
        except Exception:
            pass

    # 3) Handle concatenated objects with no newline: '}{' with optional whitespace
    try:
        fixed = re.sub(r'}\s*{', '}\n{', stripped)  # insert newline between objects
        for raw in fixed.splitlines():
            line = raw.strip()
            if line.startswith("{") and line.endswith("}"):
                recs.append(json.loads(line))
    except Exception:
        pass

    return recs

def lambda_handler(event, context):
    for rec in event.get("Records", []):
        bucket = rec["s3"]["bucket"]["name"]
        key    = rec["s3"]["object"]["key"]

        text = _read_s3_object(bucket, key)
        log.info("First 120 bytes: %s", text[:120].replace("\n", "\\n"))

        records = _robust_parse(text)
        log.info("Parsed %d records from %s", len(records), key)

        y, m, d = _derive_partitions(key)
        out_key = f"processed/{y}/{m}/{d}/part-{context.aws_request_id}.json"
        _write_lines_json(PROCESSED_BUCKET, out_key, records, raw_text=text)

    return {"status": "ok"}
