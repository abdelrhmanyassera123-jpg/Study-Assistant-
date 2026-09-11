/// بيحوّل معادلات LaTeX لنص مقروء.
/// Turns LaTeX equations into readable text.
///
/// الموديل بيكتب المعادلات LaTeX من نفسه (`$KE = \frac{1}{2} m v^2$`) حتى لو
/// البرومبت طلب غير كده — ودي مكتوبة عشان تتقرا في متصفح فيه رياضيات، مش في
/// نص عادي. الطالب بيشوف الرموز حرفية ومش فاهم حاجة.
/// The model writes equations in LaTeX of its own accord
/// (`$KE = \frac{1}{2} m v^2$`) even when the prompt asks otherwise — and that
/// is written to be typeset, not read as plain text. The student sees the
/// markup literally and understands none of it.
///
/// الحل هنا يونيكود مش عارض رياضيات: `½ m v²` بتتقرا في أي مكان — على الشاشة،
/// وفي الصفحة المصدَّرة، وفي كارت المراجعة، ولما تتنسخ في رسالة. عارض LaTeX
/// كان هيشتغل في مكان واحد بس ويسيب الباقي زي ما هو.
/// The answer here is Unicode rather than a maths renderer: `½ m v²` reads
/// everywhere — on screen, in the exported page, on a review card, and when
/// copied into a message. A LaTeX renderer would work in one place and leave
/// the rest as it was.
library;

/// فحص سريع: أغلب النصوص مفيهاش رياضيات خالص، ومش لازم تعدي على كل الأنماط.
/// A quick check: most text has no maths at all and need not run every pattern.
bool _hasMarkup(String text) =>
    text.contains(r'\') || text.contains(r'$') || text.contains('^') ||
    text.contains('_');

/// الرموز اللي ليها مقابل في يونيكود.
/// The symbols with a Unicode counterpart.
///
/// الترتيب بالطول عشان `\leq` تتحول قبل `\le` — العكس بيسيب "q" ضايعة.
/// Ordered by length so `\leq` converts before `\le`; the other way leaves a
/// stray "q".
const _symbols = <String, String>{
  // العمليات / operations
  r'\times': '×',
  r'\cdot': '·',
  r'\div': '÷',
  r'\pm': '±',
  r'\mp': '∓',
  r'\ast': '*',
  // المقارنات / comparisons
  r'\leqslant': '≤',
  r'\geqslant': '≥',
  r'\approx': '≈',
  r'\equiv': '≡',
  r'\propto': '∝',
  r'\sim': '~',
  r'\leq': '≤',
  r'\geq': '≥',
  r'\neq': '≠',
  r'\ne': '≠',
  r'\le': '≤',
  r'\ge': '≥',
  // الأسهم / arrows
  r'\Rightarrow': '⇒',
  r'\Leftarrow': '⇐',
  r'\rightarrow': '→',
  r'\leftarrow': '←',
  r'\to': '→',
  // المؤثرات / operators
  r'\partial': '∂',
  r'\nabla': '∇',
  r'\infty': '∞',
  r'\sum': '∑',
  r'\prod': '∏',
  r'\int': '∫',
  // الحروف اليونانية الكبيرة قبل الصغيرة / capital Greek before lowercase
  r'\Delta': 'Δ',
  r'\Gamma': 'Γ',
  r'\Lambda': 'Λ',
  r'\Omega': 'Ω',
  r'\Phi': 'Φ',
  r'\Pi': 'Π',
  r'\Psi': 'Ψ',
  r'\Sigma': 'Σ',
  r'\Theta': 'Θ',
  r'\alpha': 'α',
  r'\beta': 'β',
  r'\gamma': 'γ',
  r'\delta': 'δ',
  r'\varepsilon': 'ε',
  r'\epsilon': 'ε',
  r'\zeta': 'ζ',
  r'\eta': 'η',
  r'\theta': 'θ',
  r'\kappa': 'κ',
  r'\lambda': 'λ',
  r'\mu': 'μ',
  r'\nu': 'ν',
  r'\xi': 'ξ',
  r'\rho': 'ρ',
  r'\sigma': 'σ',
  r'\tau': 'τ',
  r'\phi': 'φ',
  r'\chi': 'χ',
  r'\psi': 'ψ',
  r'\omega': 'ω',
  r'\varphi': 'φ',
  r'\vartheta': 'ϑ',
  r'\varsigma': 'ς',
  r'\upsilon': 'υ',
  r'\omicron': 'ο',
  r'\iota': 'ι',
  r'\Upsilon': 'Υ',
  r'\Xi': 'Ξ',
  r'\pi': 'π',
  // الأقواس الرياضية / mathematical brackets
  r'\langle': '⟨',
  r'\rangle': '⟩',
  r'\lVert': '‖',
  r'\rVert': '‖',
  r'\lvert': '|',
  r'\rvert': '|',
  r'\vert': '|',
  r'\lbrace': '{',
  r'\rbrace': '}',
  r'\lceil': '⌈',
  r'\rceil': '⌉',
  r'\lfloor': '⌊',
  r'\rfloor': '⌋',
  // الفيزياء / physics
  r'\hbar': 'ℏ',
  r'\dagger': '†',
  r'\ddagger': '‡',
  r'\prime': '′',
  r'\ell': 'ℓ',
  r'\aleph': 'ℵ',
  // المجموعات والمنطق / sets and logic
  r'\varnothing': '∅',
  r'\emptyset': '∅',
  r'\subseteq': '⊆',
  r'\supseteq': '⊇',
  r'\subset': '⊂',
  r'\supset': '⊃',
  r'\notin': '∉',
  r'\forall': '∀',
  r'\exists': '∃',
  r'\therefore': '∴',
  r'\because': '∵',
  r'\cup': '∪',
  r'\cap': '∩',
  r'\land': '∧',
  r'\lor': '∨',
  r'\neg': '¬',
  r'\in': '∈',
  // مؤثرات / operators
  r'\otimes': '⊗',
  r'\oplus': '⊕',
  r'\odot': '⊙',
  r'\bullet': '•',
  r'\star': '⋆',
  r'\parallel': '∥',
  r'\perp': '⊥',
  r'\angle': '∠',
  r'\triangle': '△',
  // مقارنات إضافية / further comparisons
  r'\simeq': '≃',
  r'\cong': '≅',
  r'\ll': '≪',
  r'\gg': '≫',
  // أسهم إضافية / further arrows
  r'\Leftrightarrow': '⇔',
  r'\leftrightarrow': '↔',
  r'\longrightarrow': '⟶',
  r'\mapsto': '↦',
  r'\uparrow': '↑',
  r'\downarrow': '↓',
  // متنوع / assorted
  r'\cdots': '⋯',
  r'\vdots': '⋮',
  r'\ddots': '⋱',
  r'\ldots': '…',
  r'\dots': '…',
  r'\degree': '°',
  r'\circ': '∘',
  r'\%': '%',
  r'\&': '&',
  // مسافات وأقواس LaTeX مالهاش معنى في النص العادي
  // LaTeX spacing and delimiters that mean nothing in plain text
  r'\left': '',
  r'\right': '',
  r'\quad': '  ',
  r'\qquad': '    ',
  r'\,': ' ',
  r'\;': ' ',
  r'\:': ' ',
  r'\!': '',
  r'\{': '{',
  r'\}': '}',
  r'\#': '#',
  r'\_': '_',
};

/// علامات فوق الحرف: \bar و \hat وأخواتهم.
/// Marks above a letter: \bar, \hat and their family.
const _accents = <String, String>{
  'bar': '\u0304',
  'overline': '\u0304',
  'hat': '\u0302',
  'widehat': '\u0302',
  'tilde': '\u0303',
  'widetilde': '\u0303',
  'dot': '\u0307',
  'ddot': '\u0308',
  'vec': '\u20D7',
};

/// دوال بتتكتب زي ما هي من غير الشرطة.
/// Functions that keep their name without the backslash.
const _functions = [
  'arcsin', 'arccos', 'arctan', 'sinh', 'cosh', 'tanh',
  'sin', 'cos', 'tan', 'sec', 'csc', 'cot',
  'log', 'ln', 'exp', 'lim', 'max', 'min', 'det',
  'deg', 'gcd', 'dim', 'ker', 'arg', 'sup', 'inf', 'mod',
];

const _superscripts = <String, String>{
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '−': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
  'n': 'ⁿ', 'i': 'ⁱ',
};

const _subscripts = <String, String>{
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '−': '₋', '=': '₌', '(': '₍', ')': '₎',
  'a': 'ₐ', 'e': 'ₑ', 'o': 'ₒ', 'x': 'ₓ', 'h': 'ₕ', 'k': 'ₖ',
  'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'p': 'ₚ', 's': 'ₛ', 't': 'ₜ',
};

/// الكسور اللي ليها رمز واحد — أوضح من "1/2".
/// The fractions with a glyph of their own; clearer than "1/2".
const _vulgar = <String, String>{
  '1/2': '½', '1/3': '⅓', '2/3': '⅔', '1/4': '¼', '3/4': '¾',
  '1/5': '⅕', '1/8': '⅛', '3/8': '⅜', '5/8': '⅝', '7/8': '⅞',
};

/// علامة بداية عزل من الشمال لليمين، وعلامة نهايته.
/// The marks that open and close a left-to-right isolate.
const _lri = '\u2066';
const _pdi = '\u2069';

/// بيحوّط المعادلة بعزل اتجاه عشان ما تتقلبش جوه نص عربي.
/// Wraps an equation in a direction isolate so it does not flip inside Arabic
/// text.
String _isolate(String equation) {
  final body = equation.trim();
  if (body.isEmpty) return '';
  return '$_lri$body$_pdi';
}

/// بيشيل علامات العزل — للمقارنة والاختبار.
/// Strips the isolate marks, for comparison and for tests.
String withoutIsolates(String text) =>
    text.replaceAll(_lri, '').replaceAll(_pdi, '');

/// بيحوّل مجموعة حروف لأس، ولو حرف واحد مالهوش شكل بيسيبها زي ما هي.
/// Raises a group into superscript, leaving it alone if one character has no
/// raised form.
String _raise(String group, Map<String, String> table, String fallbackMark) {
  final buffer = StringBuffer();
  for (final char in group.split('')) {
    final mapped = table[char];
    // نص مقصوص أوضح من نص نصه مرفوع ونصه لأ.
    // Half-raised text reads worse than text left as it was.
    if (mapped == null) {
      return group.length == 1 ? '$fallbackMark$group' : '$fallbackMark($group)';
    }
    buffer.write(mapped);
  }
  return buffer.toString();
}

/// بيبني كسر مقروء.
/// Builds a readable fraction.
///
/// البسط والمقام اللي فيهم عملية بيتحاطوا في أقواس: `a + b/c` غامضة، و
/// `(a + b)/c` مش غامضة.
/// A numerator or denominator holding an operation is bracketed: `a + b/c` is
/// ambiguous where `(a + b)/c` is not.
String _fraction(String top, String bottom) {
  final a = top.trim();
  final b = bottom.trim();
  if (a.isEmpty || b.isEmpty) return '$a/$b';

  final vulgar = _vulgar['$a/$b'];
  if (vulgar != null) return vulgar;

  final needsBrackets = RegExp(r'[\s+\-−×·÷/]');
  final left = needsBrackets.hasMatch(a) ? '($a)' : a;
  final right = needsBrackets.hasMatch(b) ? '($b)' : b;
  return '$left/$right';
}

/// بيحوّل نص فيه LaTeX لنص مقروء.
/// Converts text containing LaTeX into readable text.
///
/// آمن على النص العادي: اللي مفيهوش علامات بيرجع زي ما هو، وتشغيلها مرتين على
/// نفس النص بيدي نفس النتيجة.
/// Safe on ordinary text: anything without markup comes back untouched, and
/// running it twice over the same text gives the same result.
String readableMath(String input) {
  if (input.isEmpty || !_hasMarkup(input)) return input;

  var text = input;

  // 1) شيل الأقواس اللي بتحوّط المعادلة، وحوّط اللي جواها بعزل اتجاه.
  // 1) Strip the delimiters wrapping an equation, and isolate what was inside.
  //
  // المعادلة بتتقرا من الشمال لليمين وهي جوه فقرة عربية بتتقرا من اليمين
  // للشمال. من غير عزل، المتصفح بيرتّبها غلط: الشرطة اللي في أول `\langle`
  // بتظهر في آخر السطر، والمعادلة بتبان مقلوبة.
  // An equation reads left to right inside a paragraph that reads right to
  // left. Without isolation the browser reorders it: the backslash starting
  // `\langle` lands at the end of the line and the equation looks scrambled.
  text = text.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$', dotAll: true), (m) => _isolate(m[1]!));
  text = text.replaceAllMapped(
      RegExp(r'\$([^$\n]+?)\$'), (m) => _isolate(m[1]!));
  text = text.replaceAllMapped(
      RegExp(r'\\\((.+?)\\\)', dotAll: true), (m) => _isolate(m[1]!));
  text = text.replaceAllMapped(
      RegExp(r'\\\[(.+?)\\\]', dotAll: true), (m) => _isolate(m[1]!));

  // 2) النص جوه \text{} بيخرج زي ما هو قبل أي تحويل تاني.
  // 2) Text inside \text{} comes out as it is, before anything else runs.
  text = text.replaceAllMapped(
    RegExp(r'\\(?:text|textbf|textit|mathrm|mathbf|mathit|operatorname)\s*\{([^{}]*)\}'),
    (m) => m[1]!,
  );

  // 3) الكسور — مرتين عشان الكسر اللي جوه كسر.
  // 3) Fractions, twice over for one nested inside another.
  for (var pass = 0; pass < 2; pass++) {
    text = text.replaceAllMapped(
      RegExp(r'\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}'),
      (m) => _fraction(m[1]!, m[2]!),
    );
  }

  // 3.5) الدرجة: `^\circ` بتتقرا درجة مش تركيب دوال.
  // 3.5) Degrees: `^\circ` reads as a degree, not as composition.
  text = text.replaceAll(r'^\circ', '°').replaceAll(r'^{\circ}', '°');

  // 3.6) العلامات فوق الحروف — الحرف الأول وبعده علامة يونيكود مركّبة.
  // 3.6) Accents: the letter, then a Unicode combining mark.
  for (final entry in _accents.entries) {
    text = text.replaceAllMapped(
      RegExp('\\\\${entry.key}\\s*\\{([^{}]*)\\}'),
      (m) {
        final inner = m[1]!;
        return inner.isEmpty ? '' : '$inner${entry.value}';
      },
    );
  }

  // 3.7) البيئات (المصفوفات وغيرها): بنشيل غلافها ونسيب محتواها.
  // 3.7) Environments (matrices and the rest): the wrapper goes, the contents
  // stay.
  text = text.replaceAll(RegExp(r'\\(?:begin|end)\s*\{[^{}]*\}'), ' ');
  text = text.replaceAll('&', ' ');

  // 4) الجذور.
  // 4) Roots.
  text = text.replaceAllMapped(
    RegExp(r'\\sqrt\s*(?:\[([^\]]*)\])?\s*\{([^{}]*)\}'),
    (m) {
      final degree = (m[1] ?? '').trim();
      final inner = m[2]!.trim();
      final root = degree.isEmpty
          ? '√'
          : '${_raise(degree, _superscripts, '')}√';
      return inner.length <= 1 ? '$root$inner' : '$root($inner)';
    },
  );

  // 5) الدوال قبل الرموز: \sin مش المفروض تتحول لـ s + رمز.
  // 5) Functions before symbols: \sin must not become s + a symbol.
  for (final name in _functions) {
    text = text.replaceAll('\\$name', name);
  }

  // 6) الرموز — الأطول الأول.
  // 6) The symbols, longest first.
  final ordered = _symbols.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in ordered) {
    text = text.replaceAll(key, _symbols[key]!);
  }

  // 7) الأسس والسفلية.
  // 7) Superscripts and subscripts.
  text = text.replaceAllMapped(
      RegExp(r'\^\{([^{}]+)\}'), (m) => _raise(m[1]!, _superscripts, '^'));
  text = text.replaceAllMapped(
      RegExp(r'\^([A-Za-z0-9+\-])'), (m) => _raise(m[1]!, _superscripts, '^'));
  text = text.replaceAllMapped(
      RegExp(r'_\{([^{}]+)\}'), (m) => _raise(m[1]!, _subscripts, '_'));
  text = text.replaceAllMapped(
      RegExp(r'_([A-Za-z0-9+\-])'), (m) => _raise(m[1]!, _subscripts, '_'));

  // 8) `\\` في LaTeX سطر جديد.
  // 8) `\\` is a line break in LaTeX.
  text = text.replaceAll(r'\\', '\n');

  // 9) الأقواس المتبقية من مجموعات اتفكت.
  // 9) Braces left over from groups that were unwrapped.
  text = text.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (m) => m[1]!);

  // 9.5) القوس بيلزق بمحتواه: LaTeX بتاكل المسافة بعد اسم الأمر، فـ
  // `\langle 0` معناها ⟨0 مش "⟨ 0".
  // 9.5) A bracket sticks to its contents: LaTeX eats the space after a command
  // name, so `\langle 0` means ⟨0 rather than "⟨ 0".
  for (final open in ['⟨', '⌈', '⌊', '‖']) {
    text = text.replaceAll('$open ', open);
  }
  for (final close in ['⟩', '⌉', '⌋']) {
    text = text.replaceAll(' $close', close);
  }

  // 10) المسافات الزيادة اللي ظهرت من الشيل.
  // 10) The extra spaces the removals left behind.
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return text;
}
