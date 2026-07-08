# == Schema Information
#
# Table name: tickets
#
#  id              :bigint           not null, primary key
#  description     :text
#  resolved_at     :datetime
#  status          :integer          default("open"), not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  assignee_id     :bigint
#  conversation_id :bigint
#  creator_id      :bigint
#  display_id      :integer          not null
#
# Indexes
#
#  index_tickets_on_account_id                  (account_id)
#  index_tickets_on_account_id_and_display_id   (account_id,display_id) UNIQUE
#  index_tickets_on_account_id_and_status       (account_id,status)
#  index_tickets_on_assignee_id_and_account_id  (assignee_id,account_id)
#  index_tickets_on_conversation_id             (conversation_id)
#
class Ticket < ApplicationRecord
  belongs_to :account
  belongs_to :assignee, class_name: 'User', optional: true, inverse_of: :assigned_tickets
  belongs_to :creator, class_name: 'User', optional: true, inverse_of: :created_tickets
  belongs_to :conversation, optional: true

  enum status: { open: 0, pending: 1, resolved: 2, closed: 3 }

  validates :title, presence: true
  validates :account_id, presence: true
  validate :validate_assignee_belongs_to_account
  validate :validate_conversation_belongs_to_account

  before_save :set_resolved_at
  after_create :load_attributes_created_by_db_triggers

  scope :latest, -> { order(created_at: :desc) }
  scope :assigned_to, ->(agent) { where(assignee_id: agent.id) }
  scope :unassigned, -> { where(assignee_id: nil) }

  def ticket_number
    "##{display_id}"
  end

  private

  # display_id is set via a database trigger (per-account sequence),
  # same pattern used by Conversation. Fetch it back after create.
  def load_attributes_created_by_db_triggers
    self[:display_id] = self.class.find(id)[:display_id]
  end

  def set_resolved_at
    if status_changed? && (resolved? || closed?)
      self.resolved_at ||= Time.current
    elsif status_changed?
      self.resolved_at = nil
    end
  end

  def validate_assignee_belongs_to_account
    return if assignee_id.blank?
    return if account&.account_users&.exists?(user_id: assignee_id)

    errors.add(:assignee, 'must be an agent or administrator of the account')
  end

  def validate_conversation_belongs_to_account
    return if conversation_id.blank?
    return if conversation&.account_id == account_id

    errors.add(:conversation, 'must belong to the same account')
  end

  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('ticket_dpid_seq_' || NEW.account_id);"
  end
end

Ticket.prepend_mod_with('Ticket')
