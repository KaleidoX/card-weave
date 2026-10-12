class ContactSection {
  final String initial;
  final int offset, count;
  const ContactSection(this.initial, this.offset, this.count);
  factory ContactSection.fromJson(Map<String, dynamic> value) => ContactSection(
    value['initial'] as String,
    value['offset'] as int,
    value['count'] as int,
  );
}
