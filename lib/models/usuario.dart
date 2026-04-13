class Usuario {
  final String id;
  final String nombre;
  final String email;
  final String? plan;
  final int creditos;
  final DateTime? creditosVencimiento;
  final String? avatarUrl;
  final String? mpSubscriptionId;
  final String? subscriptionStatus;
  final DateTime? renewalDate;
  final int? estudioAsociadoId;
  final bool notifReservas;
  final bool notifRecordatorios;
  final bool notifPromos;

  const Usuario({
    required this.id,
    required this.nombre,
    required this.email,
    this.plan,
    this.creditos = 0,
    this.creditosVencimiento,
    this.avatarUrl,
    this.mpSubscriptionId,
    this.subscriptionStatus,
    this.renewalDate,
    this.estudioAsociadoId,
    this.notifReservas = true,
    this.notifRecordatorios = true,
    this.notifPromos = false,
  });

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id']?.toString() ?? '',
      nombre: map['nombre'] ?? '',
      email: map['email'] ?? '',
      plan: map['plan'],
      creditos: (map['creditos'] as num?)?.toInt() ?? 0,
      creditosVencimiento: map['creditos_vencimiento'] != null
          ? DateTime.tryParse(map['creditos_vencimiento'].toString())
          : null,
      avatarUrl: map['avatar_url'],
      mpSubscriptionId: map['mp_subscription_id'],
      subscriptionStatus: map['subscription_status'],
      renewalDate: map['renewal_date'] != null
          ? DateTime.tryParse(map['renewal_date'].toString())
          : null,
      estudioAsociadoId: (map['estudio_asociado_id'] as num?)?.toInt(),
      notifReservas: map['notifs_reservas'] as bool? ?? true,
      notifRecordatorios: map['notifs_recordatorios'] as bool? ?? true,
      notifPromos: map['notifs_promos'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'email': email,
      'plan': plan,
      'creditos': creditos,
      'creditos_vencimiento': creditosVencimiento?.toIso8601String(),
      'avatar_url': avatarUrl,
      'mp_subscription_id': mpSubscriptionId,
      'subscription_status': subscriptionStatus,
      'renewal_date': renewalDate?.toIso8601String().split('T')[0],
      'estudio_asociado_id': estudioAsociadoId,
    };
  }

  Usuario copyWith({
    String? nombre,
    String? plan,
    int? creditos,
    DateTime? creditosVencimiento,
    String? avatarUrl,
    String? mpSubscriptionId,
    String? subscriptionStatus,
    DateTime? renewalDate,
    int? estudioAsociadoId,
  }) {
    return Usuario(
      id: id,
      nombre: nombre ?? this.nombre,
      email: email,
      plan: plan ?? this.plan,
      creditos: creditos ?? this.creditos,
      creditosVencimiento: creditosVencimiento ?? this.creditosVencimiento,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      mpSubscriptionId: mpSubscriptionId ?? this.mpSubscriptionId,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      renewalDate: renewalDate ?? this.renewalDate,
      estudioAsociadoId: estudioAsociadoId ?? this.estudioAsociadoId,
      notifReservas: notifReservas,
      notifRecordatorios: notifRecordatorios,
      notifPromos: notifPromos,
    );
  }
}
