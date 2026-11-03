/// One step in the history of a listing, order, Market Linking request or
/// enrollment: what happened, who did it and when.
///
/// Staff rows come from `workflow_events` and carry the actor's id, role and
/// (once resolved) name. A Farmer's copy comes from get_my_listing_history() and
/// carries only [by]: `you`, `cooperative` or `system`. No staff identity ever
/// reaches a Farmer or a Buyer.
class WorkflowEvent {
  final String id;
  final String? entityType;
  final String? entityId;

  /// The database action word (`approved`, `edit_requested`, `ready_for_pickup` ...).
  final String action;
  final String? fromStatus;
  final String? toStatus;

  // Staff view only.
  final String? actorId;
  final String? actorRole;
  final String? actorName;

  /// Farmer view only: you | cooperative | system.
  final String? by;

  final String? reason;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  const WorkflowEvent({
    required this.id,
    this.entityType,
    this.entityId,
    required this.action,
    this.fromStatus,
    this.toStatus,
    this.actorId,
    this.actorRole,
    this.actorName,
    this.by,
    this.reason,
    this.details = const {},
    required this.createdAt,
  });

  bool get isStaffActor => actorRole == 'admin' || actorRole == 'officer';

  WorkflowEvent withActorName(String? name) => WorkflowEvent(
    id: id,
    entityType: entityType,
    entityId: entityId,
    action: action,
    fromStatus: fromStatus,
    toStatus: toStatus,
    actorId: actorId,
    actorRole: actorRole,
    actorName: name,
    by: by,
    reason: reason,
    details: details,
    createdAt: createdAt,
  );

  factory WorkflowEvent.fromMap(Map<String, dynamic> map) {
    final details = map['details'];
    return WorkflowEvent(
      id: map['id'] as String,
      entityType: map['entity_type'] as String?,
      entityId: map['entity_id'] as String?,
      action: map['action'] as String,
      fromStatus: map['from_status'] as String?,
      toStatus: map['to_status'] as String?,
      actorId: map['actor_id'] as String?,
      actorRole: map['actor_role'] as String?,
      by: map['by'] as String?,
      reason: map['reason'] as String?,
      details: details is Map ? Map<String, dynamic>.from(details) : const {},
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}
