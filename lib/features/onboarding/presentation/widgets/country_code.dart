/// A country's name, ISO code, dial code, and flag emoji.
class CountryCode {
  const CountryCode({
    required this.name,
    required this.isoCode,
    required this.dialCode,
    required this.flag,
  });

  final String name;
  final String isoCode;
  final String dialCode;
  final String flag;

  /// Search haystack combining name, ISO code, and dial code.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        isoCode.toLowerCase().contains(q) ||
        dialCode.contains(q.startsWith('+') ? q : '+$q');
  }

  @override
  bool operator ==(Object other) =>
      other is CountryCode && other.isoCode == isoCode;

  @override
  int get hashCode => isoCode.hashCode;
}

/// Curated list of countries with their calling codes, sorted by name.
///
/// Flag emoji are built from Unicode regional indicator symbols, so they
/// render correctly on any platform with standard emoji font support.
const List<CountryCode> kCountryCodes = [
  CountryCode(
    name: 'Afghanistan',
    isoCode: 'AF',
    dialCode: '+93',
    flag: '🇦🇫',
  ),
  CountryCode(name: 'Albania', isoCode: 'AL', dialCode: '+355', flag: '🇦🇱'),
  CountryCode(name: 'Algeria', isoCode: 'DZ', dialCode: '+213', flag: '🇩🇿'),
  CountryCode(name: 'Argentina', isoCode: 'AR', dialCode: '+54', flag: '🇦🇷'),
  CountryCode(name: 'Australia', isoCode: 'AU', dialCode: '+61', flag: '🇦🇺'),
  CountryCode(name: 'Austria', isoCode: 'AT', dialCode: '+43', flag: '🇦🇹'),
  CountryCode(
    name: 'Bangladesh',
    isoCode: 'BD',
    dialCode: '+880',
    flag: '🇧🇩',
  ),
  CountryCode(name: 'Belgium', isoCode: 'BE', dialCode: '+32', flag: '🇧🇪'),
  CountryCode(name: 'Brazil', isoCode: 'BR', dialCode: '+55', flag: '🇧🇷'),
  CountryCode(name: 'Bulgaria', isoCode: 'BG', dialCode: '+359', flag: '🇧🇬'),
  CountryCode(name: 'Cambodia', isoCode: 'KH', dialCode: '+855', flag: '🇰🇭'),
  CountryCode(name: 'Canada', isoCode: 'CA', dialCode: '+1', flag: '🇨🇦'),
  CountryCode(name: 'Chile', isoCode: 'CL', dialCode: '+56', flag: '🇨🇱'),
  CountryCode(name: 'China', isoCode: 'CN', dialCode: '+86', flag: '🇨🇳'),
  CountryCode(name: 'Colombia', isoCode: 'CO', dialCode: '+57', flag: '🇨🇴'),
  CountryCode(name: 'Croatia', isoCode: 'HR', dialCode: '+385', flag: '🇭🇷'),
  CountryCode(
    name: 'Czech Republic',
    isoCode: 'CZ',
    dialCode: '+420',
    flag: '🇨🇿',
  ),
  CountryCode(name: 'Denmark', isoCode: 'DK', dialCode: '+45', flag: '🇩🇰'),
  CountryCode(name: 'Egypt', isoCode: 'EG', dialCode: '+20', flag: '🇪🇬'),
  CountryCode(name: 'Finland', isoCode: 'FI', dialCode: '+358', flag: '🇫🇮'),
  CountryCode(name: 'France', isoCode: 'FR', dialCode: '+33', flag: '🇫🇷'),
  CountryCode(name: 'Germany', isoCode: 'DE', dialCode: '+49', flag: '🇩🇪'),
  CountryCode(name: 'Ghana', isoCode: 'GH', dialCode: '+233', flag: '🇬🇭'),
  CountryCode(name: 'Greece', isoCode: 'GR', dialCode: '+30', flag: '🇬🇷'),
  CountryCode(name: 'Hong Kong', isoCode: 'HK', dialCode: '+852', flag: '🇭🇰'),
  CountryCode(name: 'Hungary', isoCode: 'HU', dialCode: '+36', flag: '🇭🇺'),
  CountryCode(name: 'India', isoCode: 'IN', dialCode: '+91', flag: '🇮🇳'),
  CountryCode(name: 'Indonesia', isoCode: 'ID', dialCode: '+62', flag: '🇮🇩'),
  CountryCode(name: 'Iran', isoCode: 'IR', dialCode: '+98', flag: '🇮🇷'),
  CountryCode(name: 'Iraq', isoCode: 'IQ', dialCode: '+964', flag: '🇮🇶'),
  CountryCode(name: 'Ireland', isoCode: 'IE', dialCode: '+353', flag: '🇮🇪'),
  CountryCode(name: 'Israel', isoCode: 'IL', dialCode: '+972', flag: '🇮🇱'),
  CountryCode(name: 'Italy', isoCode: 'IT', dialCode: '+39', flag: '🇮🇹'),
  CountryCode(name: 'Japan', isoCode: 'JP', dialCode: '+81', flag: '🇯🇵'),
  CountryCode(name: 'Jordan', isoCode: 'JO', dialCode: '+962', flag: '🇯🇴'),
  CountryCode(name: 'Kenya', isoCode: 'KE', dialCode: '+254', flag: '🇰🇪'),
  CountryCode(name: 'Kuwait', isoCode: 'KW', dialCode: '+965', flag: '🇰🇼'),
  CountryCode(name: 'Malaysia', isoCode: 'MY', dialCode: '+60', flag: '🇲🇾'),
  CountryCode(name: 'Mexico', isoCode: 'MX', dialCode: '+52', flag: '🇲🇽'),
  CountryCode(name: 'Morocco', isoCode: 'MA', dialCode: '+212', flag: '🇲🇦'),
  CountryCode(name: 'Myanmar', isoCode: 'MM', dialCode: '+95', flag: '🇲🇲'),
  CountryCode(name: 'Nepal', isoCode: 'NP', dialCode: '+977', flag: '🇳🇵'),
  CountryCode(
    name: 'Netherlands',
    isoCode: 'NL',
    dialCode: '+31',
    flag: '🇳🇱',
  ),
  CountryCode(
    name: 'New Zealand',
    isoCode: 'NZ',
    dialCode: '+64',
    flag: '🇳🇿',
  ),
  CountryCode(name: 'Nigeria', isoCode: 'NG', dialCode: '+234', flag: '🇳🇬'),
  CountryCode(name: 'Norway', isoCode: 'NO', dialCode: '+47', flag: '🇳🇴'),
  CountryCode(name: 'Pakistan', isoCode: 'PK', dialCode: '+92', flag: '🇵🇰'),
  CountryCode(
    name: 'Philippines',
    isoCode: 'PH',
    dialCode: '+63',
    flag: '🇵🇭',
  ),
  CountryCode(name: 'Poland', isoCode: 'PL', dialCode: '+48', flag: '🇵🇱'),
  CountryCode(name: 'Portugal', isoCode: 'PT', dialCode: '+351', flag: '🇵🇹'),
  CountryCode(name: 'Qatar', isoCode: 'QA', dialCode: '+974', flag: '🇶🇦'),
  CountryCode(name: 'Romania', isoCode: 'RO', dialCode: '+40', flag: '🇷🇴'),
  CountryCode(name: 'Russia', isoCode: 'RU', dialCode: '+7', flag: '🇷🇺'),
  CountryCode(
    name: 'Saudi Arabia',
    isoCode: 'SA',
    dialCode: '+966',
    flag: '🇸🇦',
  ),
  CountryCode(name: 'Singapore', isoCode: 'SG', dialCode: '+65', flag: '🇸🇬'),
  CountryCode(
    name: 'South Africa',
    isoCode: 'ZA',
    dialCode: '+27',
    flag: '🇿🇦',
  ),
  CountryCode(
    name: 'South Korea',
    isoCode: 'KR',
    dialCode: '+82',
    flag: '🇰🇷',
  ),
  CountryCode(name: 'Spain', isoCode: 'ES', dialCode: '+34', flag: '🇪🇸'),
  CountryCode(name: 'Sri Lanka', isoCode: 'LK', dialCode: '+94', flag: '🇱🇰'),
  CountryCode(name: 'Sweden', isoCode: 'SE', dialCode: '+46', flag: '🇸🇪'),
  CountryCode(
    name: 'Switzerland',
    isoCode: 'CH',
    dialCode: '+41',
    flag: '🇨🇭',
  ),
  CountryCode(name: 'Taiwan', isoCode: 'TW', dialCode: '+886', flag: '🇹🇼'),
  CountryCode(name: 'Thailand', isoCode: 'TH', dialCode: '+66', flag: '🇹🇭'),
  CountryCode(name: 'Turkey', isoCode: 'TR', dialCode: '+90', flag: '🇹🇷'),
  CountryCode(name: 'Ukraine', isoCode: 'UA', dialCode: '+380', flag: '🇺🇦'),
  CountryCode(
    name: 'United Arab Emirates',
    isoCode: 'AE',
    dialCode: '+971',
    flag: '🇦🇪',
  ),
  CountryCode(
    name: 'United Kingdom',
    isoCode: 'GB',
    dialCode: '+44',
    flag: '🇬🇧',
  ),
  CountryCode(
    name: 'United States',
    isoCode: 'US',
    dialCode: '+1',
    flag: '🇺🇸',
  ),
  CountryCode(name: 'Vietnam', isoCode: 'VN', dialCode: '+84', flag: '🇻🇳'),
];

/// Default country shown before the user picks one.
const kDefaultCountryCode = CountryCode(
  name: 'United States',
  isoCode: 'US',
  dialCode: '+1',
  flag: '🇺🇸',
);
