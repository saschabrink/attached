# Why didn't you...?

Design decisions that look "wrong" at first glance but are deliberate. If you're
about to "fix" one of these, read this first.

## ...use a more cryptographically secure checksum than MD5?

`Original.checksum` and `Variant.checksum` are MD5 hashes, base64-encoded. MD5 has
been cryptographically broken since 2004 — so why use it?

Because this checksum is for **integrity**, not **security**:

- **S3 / GCS compatibility.** Object stores accept a `Content-MD5` header
  (base64-encoded MD5) on upload and reject the request if the bytes don't
  match. This catches in-transit corruption automatically, server-side. Using
  any other hash means we can't take advantage of that round-trip check.
- **Bit-rot detection.** A periodic scan that re-hashes stored files and
  compares against the recorded checksum surfaces silent disk corruption. MD5
  is more than enough — we're not defending against an adversary who picks the
  bytes, just against random flips.
- **Transform-failure detection.** When `ImageMagick` or another transformer
  occasionally produces a zero-byte or truncated output, the recorded checksum
  diverges from what's actually on disk on the next read. MD5 catches that
  trivially.

For these use cases, MD5 has two real advantages over SHA-256: it's faster, and
its output is the format S3/GCS already speak. The collision-resistance
weakness is irrelevant — we're not using the hash to authenticate anything.

This is the same choice Rails ActiveStorage makes, for the same reasons.

## ...use the ActiveStorage schema exactly?

ActiveStorage models variants with two tables: `active_storage_variant_records`
(just `id`, `blob_id`, `variation_digest`) and a regular `active_storage_blobs`
row holding the variant's actual file metadata, linked via the polymorphic
`active_storage_attachments` table.

It's elegant — a variant *is* a blob, so every blob-level tool (mirroring,
analyzing, direct uploads, purging) works on variants for free. It also
naturally allows variants-of-variants, generic non-image derivatives, and so on.

We took a different route: one `attached_variants` table with everything
inline — `original_id`, `name`, `transform_digest`, `content_type`,
`byte_size`, `checksum`, `metadata`. Reasons:

- **One join instead of two.** Looking up a variant's content type is a single
  `get_by` against `attached_variants`. AS needs to join through
  `active_storage_attachments` to a second `active_storage_blobs` row.
- **`name` is a first-class column.** You can query "all `:thumb` variants of
  this original" directly in SQL. AS resolves variant names from the
  application-level `NamedVariant` registry, not from the DB.
- **No second random storage key per variant.** The variant's file lives at a
  deterministic path derived from the parent's key (`_variants/<parent_key>-<name>-<digest>`).
  AS allocates a fresh blob with its own random key and tracks it through the
  attachments table.
- **Clear mental model.** Two tables with explicit roles — `Original` is an
  uploaded file, `Variant` is a deterministic derivative of one — is much
  easier to hold in your head than one self-referential table where every row
  might be either. Fewer edge cases to think about: no cycles to prevent, no
  recursive cascade-delete semantics, no question of whether
  variant-of-variant is supported.

The trade-off we accept: variants are not generic blobs. You can't `mirror`
them through the same path as originals without separate logic, and
variants-of-variants is structurally impossible (a `Variant.original_id`
references an `Original`, never another `Variant`). For the common case — a few
named image/PDF derivatives per upload — that's a feature, not a limitation,
and it keeps the surface area small.
