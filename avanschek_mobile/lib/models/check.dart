class Check {
  String docDate;
  String docNumber;
  String name;
  double amount;
  int revision;

  Check({
    this.docDate = '',
    this.docNumber = '',
    this.name = '',
    this.amount = 0.0,
    this.revision = 0,
  });

  Map<String, dynamic> toJson() => {
        'doc_date': docDate,
        'doc_number': docNumber,
        'name': name,
        'amount': amount,
        'debit_account': 'Студия',
      };
}
