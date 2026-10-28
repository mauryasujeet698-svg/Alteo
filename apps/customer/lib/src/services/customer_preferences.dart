import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> alteoThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
final ValueNotifier<String> alteoPreferredLanguage = ValueNotifier<String>('English');
final ValueNotifier<String> alteoDeliveryLocation = ValueNotifier<String>('Choose your location');
final ValueNotifier<Map<String, dynamic>?> alteoLocationSelection = ValueNotifier<Map<String, dynamic>?>(null);

Future<void> loadCustomerPreferences() async {
  final store = await SharedPreferences.getInstance();
  final theme = store.getString('alteo_theme') ?? 'light';
  alteoThemeMode.value = switch (theme) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };
  const supported = ['English', 'हिन्दी', 'বাংলা', 'தமிழ்', 'తెలుగు'];
  final language = store.getString('alteo_language') ?? 'English';
  alteoPreferredLanguage.value = supported.contains(language) ? language : 'English';
  alteoDeliveryLocation.value = store.getString('alteo_delivery_location') ?? 'Choose your location';
  final savedLocation = store.getString('alteo_location_selection');
  if (savedLocation != null) {
    try {
      final decoded = jsonDecode(savedLocation);
      alteoLocationSelection.value = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      alteoLocationSelection.value = null;
    }
  }
}

Future<void> setAlteoTheme(ThemeMode mode) async {
  alteoThemeMode.value = mode;
  final value = switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    _ => 'light',
  };
  final store = await SharedPreferences.getInstance();
  await store.setString('alteo_theme', value);
}

Future<void> setAlteoLanguage(String language) async {
  const supported = ['English', 'हिन्दी', 'বাংলা', 'தமிழ்', 'తెలుగు'];
  if (!supported.contains(language)) return;
  alteoPreferredLanguage.value = language;
  final store = await SharedPreferences.getInstance();
  await store.setString('alteo_language', language);
}

String alteoText(String key) {
  const translations = <String, Map<String, String>>{
     'हिन्दी': {
      'DELIVERING TO': 'डिलीवरी का पता', 'Explore services': 'सेवाएँ देखें', 'Shopping, food and everyday essentials': 'खरीदारी, खाना और रोज़मर्रा की ज़रूरतें', 'Discover items': 'सामान खोजें', 'Listed by Alteo marketplace partners': 'Alteo के विक्रेताओं के उत्पाद', 'Search items, food and essentials': 'सामान, खाना और ज़रूरतें खोजें', 'Quick': 'क्विक', 'Shop': 'शॉप', 'Rides': 'राइड्स', 'Parcel': 'पार्सल', 'All': 'सभी', 'Groceries': 'किराना', 'Shopping': 'खरीदारी', 'Choose delivery location': 'डिलीवरी का पता चुनें', 'Use current location': 'वर्तमान स्थान इस्तेमाल करें', 'Detect your location with GPS': 'GPS से अपना स्थान पता करें', 'Choose saved address': 'सेव किया पता चुनें', 'Select from your saved delivery addresses': 'सेव किए गए पतों में से चुनें', 'Choose your location': 'अपना स्थान चुनें',
      'Home': 'होम', 'Food': 'खाना', 'Ride': 'राइड', 'Profile': 'प्रोफ़ाइल',
      'My orders': 'मेरे ऑर्डर', 'My rides': 'मेरी राइड्स', 'Saved addresses': 'सेव किए गए पते',
      'Payments': 'भुगतान', 'Payment methods': 'भुगतान के तरीके', 'Settings': 'सेटिंग्स',
      'Theme': 'थीम', 'Language': 'भाषा', 'Delete account': 'खाता हटाएँ',
      'Privacy policy': 'गोपनीयता नीति', 'About app': 'ऐप के बारे में',
      'Logout': 'लॉग आउट', 'Cancel': 'रद्द करें', 'Confirm logout?': 'लॉग आउट की पुष्टि करें?',
      'Are you sure you want to log out of your Alteo account?': 'क्या आप वाकई अपने Alteo खाते से लॉग आउट करना चाहते हैं?',
      'Confirm deletion?': 'खाता हटाने की पुष्टि करें?', 'Light': 'लाइट', 'Dark': 'डार्क',
      'Follow device': 'डिवाइस सेटिंग के अनुसार',
    },
     'বাংলা': {
      'DELIVERING TO': 'ডেলিভারি ঠিকানা', 'Explore services': 'পরিষেবা দেখুন', 'Shopping, food and everyday essentials': 'কেনাকাটা, খাবার ও নিত্যপ্রয়োজনীয় জিনিস', 'Discover items': 'পণ্য দেখুন', 'Listed by Alteo marketplace partners': 'Alteo বিক্রেতাদের পণ্য', 'Search items, food and essentials': 'পণ্য, খাবার ও প্রয়োজনীয় জিনিস খুঁজুন', 'Quick': 'কুইক', 'Shop': 'শপ', 'Rides': 'রাইড', 'Parcel': 'পার্সেল', 'All': 'সব', 'Groceries': 'মুদিখানা', 'Shopping': 'কেনাকাটা', 'Choose delivery location': 'ডেলিভারির ঠিকানা বেছে নিন', 'Use current location': 'বর্তমান অবস্থান ব্যবহার করুন', 'Detect your location with GPS': 'GPS দিয়ে অবস্থান খুঁজুন', 'Choose saved address': 'সংরক্ষিত ঠিকানা বেছে নিন', 'Select from your saved delivery addresses': 'সংরক্ষিত ডেলিভারি ঠিকানা থেকে বেছে নিন', 'Choose your location': 'আপনার অবস্থান বেছে নিন',
      'Home': 'হোম', 'Food': 'খাবার', 'Ride': 'রাইড', 'Profile': 'প্রোফাইল',
      'My orders': 'আমার অর্ডার', 'My rides': 'আমার রাইড', 'Saved addresses': 'সংরক্ষিত ঠিকানা',
      'Payments': 'পেমেন্ট', 'Payment methods': 'পেমেন্ট পদ্ধতি', 'Settings': 'সেটিংস',
      'Theme': 'থিম', 'Language': 'ভাষা', 'Delete account': 'অ্যাকাউন্ট মুছুন',
      'Privacy policy': 'গোপনীয়তা নীতি', 'About app': 'অ্যাপ সম্পর্কে',
      'Logout': 'লগ আউট', 'Cancel': 'বাতিল', 'Confirm logout?': 'লগ আউট নিশ্চিত করবেন?',
      'Light': 'লাইট', 'Dark': 'ডার্ক', 'Follow device': 'ডিভাইসের সেটিং অনুসরণ করুন',
    },
     'தமிழ்': {
      'DELIVERING TO': 'வழங்க வேண்டிய இடம்', 'Explore services': 'சேவைகளைப் பாருங்கள்', 'Shopping, food and everyday essentials': 'ஷாப்பிங், உணவு மற்றும் அன்றாடத் தேவைகள்', 'Discover items': 'பொருட்களைக் கண்டறியுங்கள்', 'Listed by Alteo marketplace partners': 'Alteo விற்பனையாளர்களின் பொருட்கள்', 'Search items, food and essentials': 'பொருட்கள், உணவு மற்றும் தேவைகளைத் தேடுங்கள்', 'Quick': 'விரைவு', 'Shop': 'ஷாப்பிங்', 'Rides': 'பயணங்கள்', 'Parcel': 'பார்சல்', 'All': 'அனைத்தும்', 'Groceries': 'மளிகை', 'Shopping': 'ஷாப்பிங்', 'Choose delivery location': 'வழங்கும் இடத்தைத் தேர்ந்தெடுக்கவும்', 'Use current location': 'தற்போதைய இடத்தைப் பயன்படுத்தவும்', 'Detect your location with GPS': 'GPS மூலம் உங்கள் இடத்தைக் கண்டறியவும்', 'Choose saved address': 'சேமித்த முகவரியைத் தேர்ந்தெடுக்கவும்', 'Select from your saved delivery addresses': 'சேமித்த முகவரிகளில் இருந்து தேர்வு செய்யவும்', 'Choose your location': 'உங்கள் இடத்தைத் தேர்ந்தெடுக்கவும்',
      'Home': 'முகப்பு', 'Food': 'உணவு', 'Ride': 'பயணம்', 'Profile': 'சுயவிவரம்',
      'My orders': 'எனது ஆர்டர்கள்', 'My rides': 'எனது பயணங்கள்', 'Saved addresses': 'சேமித்த முகவரிகள்',
      'Payments': 'கட்டணங்கள்', 'Payment methods': 'கட்டண முறைகள்', 'Settings': 'அமைப்புகள்',
      'Theme': 'தீம்', 'Language': 'மொழி', 'Delete account': 'கணக்கை நீக்கு',
      'Privacy policy': 'தனியுரிமைக் கொள்கை', 'About app': 'செயலி பற்றி',
      'Logout': 'வெளியேறு', 'Cancel': 'ரத்து செய்', 'Confirm logout?': 'வெளியேறுவதை உறுதிப்படுத்தவா?',
      'Light': 'ஒளி', 'Dark': 'இருள்', 'Follow device': 'சாதன அமைப்பைப் பின்பற்று',
    },
     'తెలుగు': {
      'DELIVERING TO': 'డెలివరీ చిరునామా', 'Explore services': 'సేవలను చూడండి', 'Shopping, food and everyday essentials': 'షాపింగ్, ఆహారం మరియు రోజువారీ అవసరాలు', 'Discover items': 'వస్తువులను కనుగొనండి', 'Listed by Alteo marketplace partners': 'Alteo విక్రేతల ఉత్పత్తులు', 'Search items, food and essentials': 'వస్తువులు, ఆహారం మరియు అవసరాలను వెతకండి', 'Quick': 'త్వరిత', 'Shop': 'షాప్', 'Rides': 'రైడ్లు', 'Parcel': 'పార్సెల్', 'All': 'అన్నీ', 'Groceries': 'కిరాణా', 'Shopping': 'షాపింగ్', 'Choose delivery location': 'డెలివరీ స్థానాన్ని ఎంచుకోండి', 'Use current location': 'ప్రస్తుత స్థానాన్ని ఉపయోగించండి', 'Detect your location with GPS': 'GPSతో మీ స్థానాన్ని గుర్తించండి', 'Choose saved address': 'సేవ్ చేసిన చిరునామాను ఎంచుకోండి', 'Select from your saved delivery addresses': 'సేవ్ చేసిన చిరునామాల నుంచి ఎంచుకోండి', 'Choose your location': 'మీ స్థానాన్ని ఎంచుకోండి',
      'Home': 'హోమ్', 'Food': 'ఆహారం', 'Ride': 'రైడ్', 'Profile': 'ప్రొఫైల్',
      'My orders': 'నా ఆర్డర్లు', 'My rides': 'నా రైడ్లు', 'Saved addresses': 'సేవ్ చేసిన చిరునామాలు',
      'Payments': 'చెల్లింపులు', 'Payment methods': 'చెల్లింపు పద్ధతులు', 'Settings': 'సెట్టింగులు',
      'Theme': 'థీమ్', 'Language': 'భాష', 'Delete account': 'ఖాతాను తొలగించండి',
      'Privacy policy': 'గోప్యతా విధానం', 'About app': 'యాప్ గురించి',
      'Logout': 'లాగ్ అవుట్', 'Cancel': 'రద్దు', 'Confirm logout?': 'లాగ్ అవుట్ నిర్ధారించాలా?',
      'Light': 'లైట్', 'Dark': 'డార్క్', 'Follow device': 'పరికర సెట్టింగ్ అనుసరించు',
    },
  };
  return translations[alteoPreferredLanguage.value]?[key] ?? key;
}

Future<void> setAlteoDeliveryLocation(
  String location, {
  Map<String, dynamic>? details,
  String source = 'manual',
}) async {
  final value = location.trim();
  if (value.isEmpty) return;
  alteoDeliveryLocation.value = value;
  final store = await SharedPreferences.getInstance();
  await store.setString('alteo_delivery_location', value);
  if (details != null) {
    final normalized = <String, dynamic>{...details, 'display_address': value, 'source': source};
    alteoLocationSelection.value = normalized;
    await store.setString('alteo_location_selection', jsonEncode(normalized));
  } else if (alteoLocationSelection.value != null) {
    final normalized = <String, dynamic>{
      ...alteoLocationSelection.value!,
      'display_address': value,
      'source': source,
    };
    alteoLocationSelection.value = normalized;
    await store.setString('alteo_location_selection', jsonEncode(normalized));
  }
}
