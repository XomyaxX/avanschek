import os
import shutil
import uuid
from datetime import datetime
from urllib.parse import parse_qs, urlparse
from flask import Flask, render_template, request, jsonify, send_from_directory
import win32com.client
import pythoncom
import requests
from PIL import Image
from pyzbar.pyzbar import decode

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_XLS = os.path.join(BASE_DIR, "avanschek.xls")
OUTPUT_DIR = os.path.join(BASE_DIR, "output")
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(UPLOAD_DIR, exist_ok=True)

PROFILE_PATH = os.path.join(BASE_DIR, "data", "profile.json")
os.makedirs(os.path.dirname(PROFILE_PATH), exist_ok=True)

DEFAULT_PROFILE = {
    "organization": "ИП Ермилов МВ",
    "department": "Офис",
    "fio": "",
    "position": "",
    "tab_number": "",
    "purpose": "Хоз расходы",
}


def load_profile():
    if os.path.exists(PROFILE_PATH):
        try:
            with open(PROFILE_PATH, "r", encoding="utf-8") as f:
                import json
                return {**DEFAULT_PROFILE, **json.load(f)}
        except Exception:
            pass
    return DEFAULT_PROFILE.copy()


def save_profile(profile):
    os.makedirs(os.path.dirname(PROFILE_PATH), exist_ok=True)
    with open(PROFILE_PATH, "w", encoding="utf-8") as f:
        import json
        json.dump(profile, f, ensure_ascii=False, indent=2)


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


@app.route("/api/profile", methods=["GET"])
def get_profile():
    return jsonify(load_profile())


@app.route("/api/profile", methods=["POST"])
def update_profile():
    try:
        payload = request.get_json(force=True)
        profile = load_profile()
        for key in DEFAULT_PROFILE:
            if key in payload:
                profile[key] = payload[key]
        save_profile(profile)
        return jsonify({"success": True, "profile": profile})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def _parse_qr_raw(qr_text):
    """Parse fiscal receipt QR string (RU format)."""
    if '?' in qr_text:
        qr_text = qr_text.split('?')[1]
    params = parse_qs(qr_text)
    t = params.get('t', [None])[0]
    s = params.get('s', [None])[0]
    fn = params.get('fn', [None])[0]
    i = params.get('i', [None])[0]
    fp = params.get('fp', [None])[0]

    if not t or not s:
        return None

    year = t[0:4]
    month = t[4:6]
    day = t[6:8]
    return {
        'doc_date': f'{day}/{month}',
        'amount': float(s),
        'doc_number': f'ФД {i}' if i else (f'ФП {fp}' if fp else (f'ФН {fn}' if fn else '')),
        'raw': qr_text,
    }


@app.route("/parse_qr_image", methods=["POST"])
def parse_qr_image():
    try:
        if 'qr_image' not in request.files:
            return jsonify({'error': 'Файл не загружен'}), 400

        file = request.files['qr_image']
        if file.filename == '':
            return jsonify({'error': 'Файл не выбран'}), 400

        # Save temporarily
        ext = os.path.splitext(file.filename)[1] or '.png'
        tmp_name = f"qr_tmp_{uuid.uuid4().hex}{ext}"
        tmp_path = os.path.join(UPLOAD_DIR, tmp_name)
        file.save(tmp_path)

        # Decode QR
        img = Image.open(tmp_path)
        decoded = decode(img)

        # Clean up temp file
        try:
            os.remove(tmp_path)
        except Exception:
            pass

        if not decoded:
            return jsonify({'error': 'QR-код не найден на изображении'}), 400

        # Take first decoded QR
        qr_text = decoded[0].data.decode('utf-8')
        parsed = _parse_qr_raw(qr_text)

        if not parsed:
            return jsonify({'error': 'QR-код найден, но не распознан как фискальный чек'}), 400

        return jsonify({
            'success': True,
            'raw': parsed['raw'],
            'parsed': {
                'doc_date': parsed['doc_date'],
                'amount': parsed['amount'],
                'doc_number': parsed['doc_number'],
            }
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route("/fetch_receipt", methods=["POST"])
def fetch_receipt():
    try:
        payload = request.get_json(force=True)
        qrraw = payload.get('qrraw')
        token = payload.get('token')

        if not qrraw:
            return jsonify({'error': 'Отсутствует qrraw'}), 400
        if not token:
            return jsonify({'error': 'Отсутствует токен API'}), 400

        url = 'https://proverkacheka.com/api/v1/check/get'
        data = {
            'token': token,
            'qrraw': qrraw,
        }

        resp = requests.post(url, data=data, timeout=30)
        resp_json = resp.json()

        if resp_json.get('code') != 1:
            error_msg = resp_json.get('message', 'Неизвестная ошибка API')
            return jsonify({'error': f'Ошибка API: {error_msg}'}), 400

        receipt_data = resp_json.get('data', {}).get('json', {})

        # Extract items
        items = []
        for item in receipt_data.get('items', []):
            items.append({
                'name': item.get('name', ''),
                'price': item.get('price', 0) / 100.0 if item.get('price') else 0,
                'quantity': item.get('quantity', 1),
                'sum': item.get('sum', 0) / 100.0 if item.get('sum') else 0,
            })

        # VAT
        vat = 0
        if 'nds10' in receipt_data:
            vat += receipt_data['nds10'] / 100.0
        if 'nds20' in receipt_data:
            vat += receipt_data['nds20'] / 100.0
        if 'ndsNo' in receipt_data:
            vat += receipt_data['ndsNo'] / 100.0

        # DateTime
        dt_raw = receipt_data.get('dateTime', '')
        doc_date = ''
        if dt_raw and len(dt_raw) >= 10:
            try:
                dt = datetime.fromisoformat(dt_raw.replace('Z', '+00:00'))
                doc_date = dt.strftime('%d/%m')
            except Exception:
                pass

        return jsonify({
            'success': True,
            'shop': receipt_data.get('organization', {}).get('name', ''),
            'items': items,
            'total': receipt_data.get('totalSum', 0) / 100.0,
            'vat': vat,
            'doc_date': doc_date,
            'raw': receipt_data,
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == "__main__":
    # Run on all interfaces so phone on same WiFi can connect
    app.run(host="0.0.0.0", port=5000, debug=True)
