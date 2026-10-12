import '../../contact_mapper.dart';
import 'dates.dart';

/// realme owns whole-contact conversion; unchanged fields reuse Android rules.
class RealmeContactMapper extends AndroidContactMapper {
  final RealmeEventDates dates;
  RealmeContactMapper(SolarToLunar convertSolarToLunar)
    : dates = RealmeEventDates(convertSolarToLunar);

  @override
  Future<Map<String, dynamic>?> decodeEventDate(Map<String, dynamic> row) =>
      dates.decode(row);
}
