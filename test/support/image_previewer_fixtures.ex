defmodule Attached.Test.ImagePreviewerFixtures do
  @moduledoc false

  @doc "Writes a minimal valid single-page PDF and returns its path."
  def minimal_pdf_path do
    path =
      Path.join(System.tmp_dir!(), "previewer_test_#{System.unique_integer([:positive])}.pdf")

    File.write!(path, """
    %PDF-1.4
    1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] >> endobj
    xref
    0 4
    0000000000 65535 f\r
    0000000009 00000 n\r
    0000000058 00000 n\r
    0000000115 00000 n\r
    trailer << /Size 4 /Root 1 0 R >>
    startxref
    190
    %%EOF
    """)

    path
  end

  @doc """
  Writes a minimal valid EPUB3 with `test/support/fixtures/header.png`
  flagged as the cover image, and returns its path.
  """
  def minimal_epub_path do
    path =
      Path.join(System.tmp_dir!(), "previewer_test_#{System.unique_integer([:positive])}.epub")

    cover_png = File.read!("test/support/fixtures/header.png")

    container_xml = ~s(<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>)

    content_opf = ~s(<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">test-book</dc:identifier>
    <dc:title>Test</dc:title>
    <dc:language>en</dc:language>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="cover-image" href="cover.png" media-type="image/png" properties="cover-image"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine>
    <itemref idref="nav"/>
  </spine>
</package>)

    nav_xhtml = ~s(<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Test</title></head>
<body><nav epub:type="toc"><ol><li><a href="nav.xhtml">Test</a></li></ol></nav></body>
</html>)

    files = [
      {~c"mimetype", "application/epub+zip"},
      {~c"META-INF/container.xml", container_xml},
      {~c"OEBPS/content.opf", content_opf},
      {~c"OEBPS/nav.xhtml", nav_xhtml},
      {~c"OEBPS/cover.png", cover_png}
    ]

    {:ok, _} = :zip.create(String.to_charlist(path), files)
    path
  end
end
