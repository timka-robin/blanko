import Foundation

enum FileTemplates {
    static func textDocument() -> Data {
        Data()
    }

    static func wordDocument() -> Data {
        ZipWriter.archive(entries: [
            ("[Content_Types].xml", xml(contentTypesWord)),
            ("_rels/.rels", xml(relsRoot)),
            ("word/document.xml", xml(documentWord)),
        ])
    }

    static func excelWorkbook() -> Data {
        ZipWriter.archive(entries: [
            ("[Content_Types].xml", xml(contentTypesExcel)),
            ("_rels/.rels", xml(relsRootExcel)),
            ("xl/workbook.xml", xml(workbookExcel)),
            ("xl/_rels/workbook.xml.rels", xml(relsWorkbook)),
            ("xl/worksheets/sheet1.xml", xml(sheetExcel)),
        ])
    }

    private static func xml(_ body: String) -> Data {
        Data(body.utf8)
    }

    private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    private static var contentTypesWord: String {
        header + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/word/document.xml" \
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        </Types>
        """
    }

    private static var contentTypesExcel: String {
        header + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/xl/workbook.xml" \
        ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/worksheets/sheet1.xml" \
        ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
        </Types>
        """
    }

    private static var relsRoot: String {
        header + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" \
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
        Target="word/document.xml"/></Relationships>
        """
    }

    private static var relsRootExcel: String {
        header + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" \
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
        Target="xl/workbook.xml"/></Relationships>
        """
    }

    private static var documentWord: String {
        header + """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:body><w:p/><w:sectPr/></w:body></w:document>
        """
    }

    private static var workbookExcel: String {
        header + """
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
    }

    private static var relsWorkbook: String {
        header + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" \
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" \
        Target="worksheets/sheet1.xml"/></Relationships>
        """
    }

    private static var sheetExcel: String {
        header + """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetData/></worksheet>
        """
    }
}
