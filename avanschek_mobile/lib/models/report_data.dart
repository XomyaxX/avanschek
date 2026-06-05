class ReportData {
  String organization;
  String department;
  String fio;
  String position;
  String tabNumber;
  String purpose;
  String reportNumber;
  String reportDate;
  double advanceReceived;
  String fnsToken;

  ReportData({
    this.organization = 'ИП Ермилов МВ',
    this.department = 'Офис',
    this.fio = '',
    this.position = '',
    this.tabNumber = '',
    this.purpose = 'Хоз расходы',
    this.reportNumber = '',
    this.reportDate = '',
    this.advanceReceived = 0.0,
    this.fnsToken = '',
  });

  String get shortFio {
    final parts = fio.trim().split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      return '${parts[0]} ${parts[1][0]}${parts[2][0]}';
    } else if (parts.length == 2) {
      return '${parts[0]} ${parts[1][0]}';
    }
    return fio;
  }

  Map<String, dynamic> toJson() => {
        'organization': organization,
        'department': department,
        'fio': fio,
        'fio_short': shortFio,
        'position': position,
        'tab_number': tabNumber,
        'purpose': purpose,
        'report_number': reportNumber,
        'report_date': reportDate,
        'advance_received': advanceReceived.toString(),
      };
}
