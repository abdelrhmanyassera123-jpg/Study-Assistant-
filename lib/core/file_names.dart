/// تطبيقات كتير بتشارك الملف باسم من غير امتداد ("audio-123")، والتطبيق
/// بيعرف النوع من الامتداد — فبيتضاف من نوع الملف.
/// Many apps share a file under a name with no extension ("audio-123"), and
/// the app tells types apart by extension — so one is added from the type.
String withExtension(String name, String mimeType) {
  if (RegExp(r'\.[A-Za-z0-9]{2,5}$').hasMatch(name)) return name;
  final ext = switch (mimeType.split(';').first.trim().toLowerCase()) {
    'audio/mp4' || 'audio/x-m4a' || 'audio/m4a' || 'audio/aac' => 'm4a',
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/ogg' || 'audio/opus' => 'ogg',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
    'audio/webm' => 'webm',
    'audio/flac' => 'flac',
    'audio/3gpp' || 'video/3gpp' => '3gp',
    'video/mp4' => 'mp4',
    'video/webm' => 'webm',
    'video/quicktime' => 'mov',
    'application/pdf' => 'pdf',
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'text/plain' => 'txt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' => 'pptx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'docx',
    _ => '',
  };
  return ext.isEmpty ? name : '$name.$ext';
}
