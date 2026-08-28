FactoryBot.define do
  factory :ticket, class: 'Helic3::Ticket' do
    account
    sequence(:title) { |n| "Ticket #{n}" }
    description { 'Sample ticket description' }
    status { :open }
  end
end
