// Audio / subtitle language preferences (same rules as the Kodi add-on).
import 'strings.dart';

class Lang {
  final Set<String> codes;
  final List<String> words;
  final String fr;
  final String en;
  const Lang(this.codes, this.words, this.fr, this.en);
  String get label => t('live') == 'TV en direct' ? fr : en;
}

const langs = <int, Lang>{
  1: Lang({'fr', 'fre', 'fra'}, ['french', 'francais', 'français', 'vff', 'vfq', 'vfi', 'truefrench', 'vf'], 'Français', 'French'),
  2: Lang({'en', 'eng'}, ['english', 'anglais'], 'Anglais', 'English'),
  3: Lang({'nl', 'dut', 'nld'}, ['dutch', 'nederlands', 'flemish', 'vlaams', 'néerlandais'], 'Néerlandais', 'Dutch'),
  4: Lang({'de', 'ger', 'deu'}, ['german', 'deutsch', 'allemand'], 'Allemand', 'German'),
  5: Lang({'es', 'spa'}, ['spanish', 'español', 'espanol', 'castellano', 'espagnol'], 'Espagnol', 'Spanish'),
  6: Lang({'it', 'ita'}, ['italian', 'italiano', 'italien'], 'Italien', 'Italian'),
  7: Lang({'ar', 'ara'}, ['arabic', 'arabe'], 'Arabe', 'Arabic'),
  8: Lang({'pt', 'por'}, ['portuguese', 'português', 'portugais'], 'Portugais', 'Portuguese'),
  9: Lang({'tr', 'tur'}, ['turkish', 'türkçe', 'turc'], 'Turc', 'Turkish'),
};

const subKodi = 0, subOff = 1, subAlways = 2, subForeign = 3, subForced = 4;
const _skipWords = ['commentary', 'commentaire', 'audio description', 'audiodescription', 'description audio'];

bool langMatches(String? language, String? title, int lang) {
  final l = langs[lang];
  if (l == null) return false;
  final code = (language ?? '').toLowerCase().split('-').first;
  if (l.codes.contains(code)) return true;
  final name = (title ?? '').toLowerCase();
  final tokens = name.split(RegExp(r'[^\wçéèêäöüñ]+')).toSet();
  return l.words.any((w) => w.length <= 4 ? tokens.contains(w) : name.contains(w));
}

/// Picks the best track index from (language, title, forced) tuples.
int? pickTrack(List<(String?, String?, bool)> tracks, int lang, {bool? forced}) {
  var found = <int>[];
  for (var i = 0; i < tracks.length; i++) {
    if (langMatches(tracks[i].$1, tracks[i].$2, lang)) found.add(i);
  }
  if (forced != null) {
    found = found
        .where((i) => tracks[i].$3 == forced || (forced && (tracks[i].$2 ?? '').toLowerCase().contains('forc')))
        .toList();
  }
  final clean = found.where((i) => !_skipWords.any((w) => (tracks[i].$2 ?? '').toLowerCase().contains(w))).toList();
  final best = clean.isNotEmpty ? clean : found;
  return best.isEmpty ? null : best.first;
}
