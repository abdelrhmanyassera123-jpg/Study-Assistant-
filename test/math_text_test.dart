import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/math_text.dart';

/// بيحوّل وبيشيل علامات العزل — المقارنة على النص نفسه.
/// Converts and strips the isolate marks; the comparison is on the text itself.
String plain(String input) => withoutIsolates(readableMath(input));

void main() {
  group('plain text', () {
    // أغلب التلخيصات مفيهاش رياضيات خالص، ولازم تعدي زي ما هي بالحرف.
    // Most summaries hold no maths at all, and must pass through untouched.
    test('is left exactly as it is', () {
      const text = 'الطاقة الحركية بتزيد بزيادة السرعة، وده معناه إن الجسم\n'
          'الأسرع بيحتاج شغل أكبر عشان يقف.';

      expect(readableMath(text), text);
    });

    test('an empty string stays empty', () {
      expect(readableMath(''), '');
    });
  });

  group('delimiters', () {
    test('inline dollars are unwrapped', () {
      expect(plain(r'القانون: $E = mc^2$'), 'القانون: E = mc²');
    });

    test('display dollars are unwrapped', () {
      expect(plain(r'$$a + b$$'), 'a + b');
    });

    test('bracket delimiters are unwrapped', () {
      expect(plain(r'\(x = 1\)'), 'x = 1');
      expect(plain(r'\[y = 2\]'), 'y = 2');
    });

    // السعر بالدولار مش معادلة، ومفيش سبب يخليه يتغير.
    // A price in dollars is not an equation and has no reason to change.
    test('a lone dollar sign is not treated as an equation', () {
      expect(readableMath(r'التكلفة $5 والباقي بعدين'),
          r'التكلفة $5 والباقي بعدين');
    });
  });

  group('fractions', () {
    test('a common fraction becomes one glyph', () {
      expect(readableMath(r'\frac{1}{2}'), '½');
      expect(readableMath(r'\frac{3}{4}'), '¾');
    });

    test('an ordinary fraction becomes a slash', () {
      expect(readableMath(r'\frac{W}{t}'), 'W/t');
    });

    // "a + b/c" غامضة: مش واضح البسط إيه. الأقواس بتشيل الغموض.
    // "a + b/c" is ambiguous about what the numerator is; brackets remove it.
    test('an operation inside a fraction is bracketed', () {
      expect(readableMath(r'\frac{a + b}{c}'), '(a + b)/c');
      expect(readableMath(r'\frac{v}{a - b}'), 'v/(a - b)');
    });

    test('a fraction inside a fraction is unwrapped too', () {
      expect(readableMath(r'\frac{\frac{1}{2}}{x}'), '½/x');
    });
  });

  group('powers and indices', () {
    test('digits become raised digits', () {
      expect(readableMath(r'v^2'), 'v²');
      expect(readableMath(r'x^{10}'), 'x¹⁰');
    });

    test('indices become lowered characters', () {
      expect(readableMath(r'v_0'), 'v₀');
      expect(readableMath(r'a_{max}'), 'aₘₐₓ');
    });

    // نص نصه مرفوع ونصه لأ أوحش من نص ما اتغيّرش: الحرف اللي مالوش شكل مرفوع
    // بيخلي المجموعة كلها تفضل بعلامتها.
    // Half-raised text reads worse than text left alone: one character without
    // a raised form keeps the whole group as it was.
    test('a group with no raised form keeps its marker', () {
      expect(readableMath(r'x^{abc}'), 'x^(abc)');
    });
  });

  group('symbols', () {
    test('operators become their signs', () {
      expect(readableMath(r'F \times d'), 'F × d');
      expect(readableMath(r'W = F \cdot d'), 'W = F · d');
      expect(readableMath(r'a \div b'), 'a ÷ b');
    });

    // "\leq" لازم تتحول قبل "\le"، وإلا بتفضل "q" ضايعة في النص.
    // "\leq" must convert before "\le", otherwise a stray "q" is left behind.
    test('a longer name wins over the shorter one inside it', () {
      expect(readableMath(r'x \leq y'), 'x ≤ y');
      expect(readableMath(r'x \geq y'), 'x ≥ y');
    });

    test('Greek letters come through', () {
      expect(readableMath(r'\theta + \alpha'), 'θ + α');
      expect(readableMath(r'\Delta v'), 'Δ v');
    });

    test('functions keep their names', () {
      expect(readableMath(r'\cos(\theta)'), 'cos(θ)');
      expect(readableMath(r'\sin x + \ln y'), 'sin x + ln y');
    });

    test('roots are readable', () {
      expect(readableMath(r'\sqrt{2}'), '√2');
      expect(readableMath(r'\sqrt{x + 1}'), '√(x + 1)');
    });
  });

  group('leftovers', () {
    test('sizing commands disappear', () {
      expect(readableMath(r'\left( x \right)'), '( x )');
    });

    test('text inside \\text comes out as text', () {
      expect(readableMath(r'\text{الشغل} = F d'), 'الشغل = F d');
    });

    // الأقواس بتتشال جوه نص فيه LaTeX بس. القوس في نص عادي مش علامة تنسيق —
    // ممكن يكون جزء من كود أو من كلام المحاضر.
    // Braces are cleaned only inside text that carries LaTeX. A brace in
    // ordinary text is not markup: it could be code, or something the lecturer
    // actually said.
    test('stray groups lose their braces inside an equation', () {
      expect(readableMath(r'x^2 {abc}'), 'x² abc');
    });

    test('braces in ordinary text are left alone', () {
      expect(readableMath('الكود بيبدأ بـ {ودي مش معادلة}'),
          'الكود بيبدأ بـ {ودي مش معادلة}');
    });
  });

  group('whole equations', () {
    test('the laws a physics summary actually contains', () {
      expect(plain(r'$KE = \frac{1}{2} m v^2$'), 'KE = ½ m v²');
      expect(
        plain(r'$W = F \cdot d \cdot \cos(\theta)$'),
        'W = F · d · cos(θ)',
      );
      expect(plain(r'$d = v_0 t + \frac{1}{2} a t^2$'), 'd = v₀ t + ½ a t²');
      expect(plain(r'$v_f^2 = v_0^2 + 2 a d$'), 'v_f² = v₀² + 2 a d');
      expect(plain(r'$P = \frac{W}{t}$'), 'P = W/t');
    });

    test('an equation inside a sentence keeps the sentence', () {
      expect(
        plain(r'القانون هو $E = mc^2$ وده بيوضح العلاقة.'),
        'القانون هو E = mc² وده بيوضح العلاقة.',
      );
    });
  });

  group('advanced physics', () {
    // دي المعادلات اللي طلعت غريبة فعلاً في تلخيص محاضرة نسبية.
    // These are the equations that actually came out unreadable in a summary of
    // a relativity lecture.
    test('bra-ket notation reads as brackets', () {
      expect(
        plain(r'$\langle 0 \vert T_{\mu\nu} \vert 0 \rangle \neq 0$'),
        '⟨0 | T_(μν) | 0⟩ ≠ 0',
      );
    });

    test('physics symbols have their glyphs', () {
      expect(plain(r'\hbar \omega'), 'ℏ ω');
      expect(plain(r'A \otimes B'), 'A ⊗ B');
      expect(plain(r'x \in S'), 'x ∈ S');
      expect(plain(r'\psi \dagger'), 'ψ †');
    });

    test('accents sit on their letter', () {
      expect(plain(r'\bar{\psi}'), 'ψ̄');
      expect(plain(r'\hat{H}'), 'Ĥ');
      expect(plain(r'\vec{v}'), 'v⃗');
    });

    test('degrees are degrees, not composition', () {
      expect(plain(r'90^\circ'), '90°');
      expect(plain(r'f \circ g'), 'f ∘ g');
    });

    test('an environment loses its wrapper, not its contents', () {
      expect(
        plain(r'\begin{pmatrix} a & b \end{pmatrix}').trim(),
        'a b',
      );
    });

    test('a root with a degree keeps it', () {
      expect(plain(r'\sqrt[3]{x}'), '³√x');
    });
  });

  group('direction', () {
    // المعادلة بتتقرا شمال-يمين جوه فقرة عربية يمين-شمال. من غير عزل، المتصفح
    // بيرمي الشرطة لآخر السطر والمعادلة بتبان مقلوبة.
    // An equation reads left to right inside a right-to-left paragraph. Without
    // an isolate the browser throws the backslash to the end of the line and the
    // equation looks scrambled.
    test('an equation is wrapped in a direction isolate', () {
      final out = readableMath(r'القانون هو $E = mc^2$ وخلاص');

      expect(out, contains('\u2066'));
      expect(out, contains('\u2069'));
      expect(withoutIsolates(out), 'القانون هو E = mc² وخلاص');
    });

    test('ordinary text gets no marks', () {
      const text = 'مفيش معادلات هنا خالص';
      expect(readableMath(text), text);
    });
  });

  group('running twice', () {
    // العرض بيحوّل، والحفظ بيحوّل. لو التحويل مش ثابت، النص بيتشوّه مع كل مرة.
    // Display converts and saving converts. If the conversion were not stable,
    // the text would degrade a little on every pass.
    test('changes nothing the second time', () {
      const samples = [
        r'$KE = \frac{1}{2} m v^2$',
        r'$W = F \cdot d$',
        'نص عادي من غير رياضيات',
        r'\sqrt{x + 1} \geq 0',
      ];

      for (final sample in samples) {
        final once = readableMath(sample);
        expect(readableMath(once), once, reason: sample);
      }
    });
  });
}
