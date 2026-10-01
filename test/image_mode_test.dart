import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/summarize/style_profile.dart';

void main() {
  const profile = StyleProfile();

  test('no pictures: the model is told to add none', () {
    final prompt = VisualPrompts.blocksSystem(profile, images: ImageMode.none);
    expect(prompt, contains('متحطش أي بلوك "image" خالص'));
    expect(prompt, isNot(contains('"query" اسم الموضوع')));
  });

  test('illustrations only: never a slide page', () {
    final prompt = VisualPrompts.blocksSystem(profile, images: ImageMode.web);
    expect(prompt, contains('متستخدمش "page"'));
    expect(prompt, isNot(contains('رقم الصفحة، أول صفحة = 1')));
  });

  test('with slides: a page comes first, Wikipedia second', () {
    final prompt = VisualPrompts.blocksSystem(profile, images: ImageMode.slides);
    expect(prompt, contains('رقم الصفحة، أول صفحة = 1'));
    expect(prompt, contains('"query" اسم الموضوع'));
  });

  test('an unknown saved value falls back to illustrations', () {
    expect(ImageMode.parse('garbage'), ImageMode.web);
    expect(ImageMode.parse('none'), ImageMode.none);
  });
}
