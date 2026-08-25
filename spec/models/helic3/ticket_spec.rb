require 'rails_helper'

RSpec.describe Helic3::Ticket, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:assignee).class_name('User').optional }
    it { is_expected.to belong_to(:creator).class_name('User').optional }
    it { is_expected.to belong_to(:conversation).optional }
  end

  describe 'display_id' do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }

    it 'assigns sequential per-account ticket numbers via the db trigger' do
      first_ticket = create(:ticket, account: account)
      second_ticket = create(:ticket, account: account)
      other_account_ticket = create(:ticket, account: other_account)

      expect(first_ticket.display_id).to eq(1)
      expect(second_ticket.display_id).to eq(2)
      expect(other_account_ticket.display_id).to eq(1)
      expect(second_ticket.ticket_number).to eq('#2')
    end
  end

  describe 'assignee validation' do
    let(:account) { create(:account) }

    it 'allows assigning an agent of the account' do
      agent = create(:user, account: account, role: :agent)
      ticket = build(:ticket, account: account, assignee: agent)

      expect(ticket).to be_valid
    end

    it 'rejects an assignee from another account' do
      outsider = create(:user)
      ticket = build(:ticket, account: account, assignee: outsider)

      expect(ticket).not_to be_valid
      expect(ticket.errors[:assignee]).to be_present
    end
  end

  describe 'resolved_at' do
    let(:account) { create(:account) }

    it 'sets resolved_at when the ticket is resolved and clears it on reopen' do
      ticket = create(:ticket, account: account)
      expect(ticket.resolved_at).to be_nil

      ticket.update!(status: :resolved)
      expect(ticket.resolved_at).to be_present

      ticket.update!(status: :open)
      expect(ticket.resolved_at).to be_nil
    end
  end
end
