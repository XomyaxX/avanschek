import os
import shutil
import uuid
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_from_directory
import win32com.client
import pythoncom

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_XLS = os.path.join(BASE_DIR, "avanschek.xls")
OUTPUT_DIR = os.path.join(BASE_DIR, "output")
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(UPLOAD_DIR, exist_ok=True)


def excel_col_letter(col_idx_0based):
    """Convert 0-based column index to Excel letter (0->A, 25->Z, 26->AA)."""
    col = col_idx_0based
    result = ""
    while col >= 0:
        result = chr(col % 26 + ord('A')) + result
        col = col // 26 - 1
    return result


def fill_excel(data, checks):
    """
    data: dict with keys:
      - organization, fio, position, tab_number, purpose, department,
        report_number, report_date (DD.MM.YYYY), advance_received
    checks: list of dicts with keys:
      - doc_date (DD.MM), doc_number, name, amount (float), debit_account
    Returns: (xls_path, pdf_path)
    """
    uid = uuid.uuid4().hex[:8]
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename_base = f"AO1_{timestamp}_{uid}"
    xls_path = os.path.join(OUTPUT_DIR, f"{filename_base}.xls")
    pdf_path = os.path.join(OUTPUT_DIR, f"{filename_base}.pdf")

    # Copy template
    shutil.copy(TEMPLATE_XLS, xls_path)

    pythoncom.CoInitialize()
    excel = win32com.client.Dispatch("Excel.Application")
    excel.Visible = False
    excel.DisplayAlerts = False

    try:
        wb = excel.Workbooks.Open(xls_path)
        sheet = wb.Worksheets(1)

        # --- Front side ---
        # Organization (A7) - merged A7:AL7
        if data.get("organization"):
            sheet.Range("A7").Value = data["organization"]

        # Report total amount (sum of checks)
        total = sum(float(c.get("amount", 0) or 0) for c in checks)
        rub = int(total)
        kop = int(round((total - rub) * 100))

        # AQ10 = rub (merged AQ10:BC10), AX11 = kop (merged AX11:AZ11)
        sheet.Range("AQ10").Value = rub
        sheet.Range("AX11").Value = kop

        # Report number/date (Z13)
        if data.get("report_number"):
            sheet.Range("Z13").Value = data["report_number"]

        # Date: day month year (row 16)
        # AM16:AN16 = day, AP16:AW16 = month, AX16:AY16 = "20", AZ16:BA16 = year last two digits
        if data.get("report_date"):
            try:
                dt = datetime.strptime(data["report_date"], "%d.%m.%Y")
                sheet.Range("AM16").Value = dt.strftime("%d")
                sheet.Range("AP16").Value = dt.strftime("%m")
                year_str = dt.strftime("%Y")
                if len(year_str) == 4:
                    sheet.Range("AX16").Value = year_str[0:2]
                    sheet.Range("AZ16").Value = year_str[2:4]
            except Exception:
                pass

        # Subordinate person (K20) - merged K20:AC20
        if data.get("fio"):
            sheet.Range("K20").Value = data["fio"]

        # Position (N22) - merged N22:AC22
        if data.get("position"):
            sheet.Range("N22").Value = data["position"]

        # Purpose (AI22) - merged AI22:BC22
        if data.get("purpose"):
            sheet.Range("AI22").Value = data["purpose"]

        # Department (P19) - merged P19:AC19
        if data.get("department"):
            sheet.Range("P19").Value = data["department"]

        # Advance received amount (row 27)
        adv = float(data.get("advance_received") or 0)
        if adv > 0:
            sheet.Range("Y27").Value = adv

        # --- Back side: expense table (starts at row 63 in Excel) ---
        start_row = 63
        for i, check in enumerate(checks):
            row = start_row + i
            # A63:E63 = № п/п (merged)
            sheet.Range(f"A{row}").Value = i + 1
            # F63:J63 = date doc (merged)
            if check.get("doc_date"):
                sheet.Range(f"F{row}").Value = check["doc_date"]
            # K63:X63 = doc description (merged) - combine number and name
            desc_parts = []
            if check.get("doc_number"):
                desc_parts.append(check["doc_number"])
            if check.get("name"):
                desc_parts.append(check["name"])
            if desc_parts:
                sheet.Range(f"K{row}").Value = ", ".join(desc_parts)
            # Y63:AD63 = amount by report (merged)
            amt = float(check.get("amount", 0) or 0)
            sheet.Range(f"Y{row}").Value = amt
            # AK63:AP63 = accepted for accounting (merged)
            sheet.Range(f"AK{row}").Value = amt
            # AW63:BC63 = debit account (merged)
            if check.get("debit_account"):
                sheet.Range(f"AW{row}").Value = check["debit_account"]

        # Totals
        # Row 30 = Итого получено
        if adv > 0:
            sheet.Range("Y30").Value = adv
        # Row 31 = Израсходовано
        sheet.Range("Y31").Value = total
        # Row 32 = Остаток, Row 33 = Перерасход
        remainder = adv - total
        if remainder >= 0:
            sheet.Range("Y32").Value = remainder
            sheet.Range("Y33").Value = 0
        else:
            sheet.Range("Y32").Value = 0
            sheet.Range("Y33").Value = abs(remainder)

        # Save XLS
        wb.Save()

        # Export to PDF
        wb.ExportAsFixedFormat(0, pdf_path)

        wb.Close(False)
    finally:
        excel.Quit()
        pythoncom.CoUninitialize()

    return xls_path, pdf_path


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/generate", methods=["POST"])
def generate():
    try:
        payload = request.get_json(force=True)
        data = payload.get("data", {})
        checks = payload.get("checks", [])

        if not checks:
            return jsonify({"error": "Добавьте хотя бы один чек"}), 400

        xls_path, pdf_path = fill_excel(data, checks)

        xls_name = os.path.basename(xls_path)
        pdf_name = os.path.basename(pdf_path)

        return jsonify({
            "success": True,
            "xls": f"/download/{xls_name}",
            "pdf": f"/download/{pdf_name}",
            "xls_name": xls_name,
            "pdf_name": pdf_name,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/download/<filename>")
def download(filename):
    return send_from_directory(OUTPUT_DIR, filename, as_attachment=True)


if __name__ == "__main__":
    # Run on all interfaces so phone on same WiFi can connect
    app.run(host="0.0.0.0", port=5000, debug=True)
