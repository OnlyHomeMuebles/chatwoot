json.id resource.id
json.display_id resource.display_id
json.ticket_number resource.ticket_number
json.title resource.title
json.description resource.description
json.status resource.status
json.conversation_id resource.conversation_id
json.resolved_at resource.resolved_at
json.created_at resource.created_at
json.updated_at resource.updated_at

if resource.assignee.present?
  json.assignee do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.assignee
  end
else
  json.assignee nil
end

if resource.creator.present?
  json.creator do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.creator
  end
else
  json.creator nil
end
