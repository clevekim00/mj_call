class CallRecording {
  const CallRecording({
    required this.path,
    required this.startedAt,
    required this.durationMs,
    this.interrupted = false,
  });
  final String path;
  final DateTime startedAt;
  final int durationMs;
  final bool interrupted;
  Map<String, dynamic> toJson() => {
    'path': path,
    'startedAt': startedAt.toIso8601String(),
    'durationMs': durationMs,
    'interrupted': interrupted,
  };
  factory CallRecording.fromJson(Map<String, dynamic> j) => CallRecording(
    path: j['path'] as String,
    startedAt: DateTime.parse(j['startedAt'] as String),
    durationMs: j['durationMs'] as int,
    interrupted: j['interrupted'] == true,
  );
}

class CallRecord {
  const CallRecord({
    required this.id,
    required this.createdAt,
    required this.organization,
    this.phone = '',
    required this.purpose,
    this.questions = '',
    this.allowedInfo = '',
    this.notes = '',
    this.outcome = 'notReviewed',
    this.completed = false,
    this.recordingIncomplete = false,
    this.recordings = const [],
  });
  final String id;
  final DateTime createdAt;
  final String organization,
      phone,
      purpose,
      questions,
      allowedInfo,
      notes,
      outcome;
  final bool completed;
  final bool recordingIncomplete;
  final List<CallRecording> recordings;

  CallRecord copyWith({
    String? notes,
    String? outcome,
    bool? completed,
    bool? recordingIncomplete,
    List<CallRecording>? recordings,
  }) => CallRecord(
    id: id,
    createdAt: createdAt,
    organization: organization,
    phone: phone,
    purpose: purpose,
    questions: questions,
    allowedInfo: allowedInfo,
    notes: notes ?? this.notes,
    outcome: outcome ?? this.outcome,
    completed: completed ?? this.completed,
    recordingIncomplete: recordingIncomplete ?? this.recordingIncomplete,
    recordings: recordings ?? this.recordings,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'organization': organization,
    'phone': phone,
    'purpose': purpose,
    'questions': questions,
    'allowedInfo': allowedInfo,
    'notes': notes,
    'outcome': outcome,
    'completed': completed,
    'recordingIncomplete': recordingIncomplete,
    'recordings': recordings.map((r) => r.toJson()).toList(),
  };
  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
    id: j['id'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    organization: j['organization'] as String,
    phone: j['phone'] as String? ?? '',
    purpose: j['purpose'] as String,
    questions: j['questions'] as String? ?? '',
    allowedInfo: j['allowedInfo'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    outcome: j['outcome'] as String? ?? 'notReviewed',
    completed: j['completed'] == true,
    recordingIncomplete: j['recordingIncomplete'] == true,
    recordings: (j['recordings'] as List? ?? [])
        .map((r) => CallRecording.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
  );
}
