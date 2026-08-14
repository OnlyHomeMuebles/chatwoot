FactoryBot.define do
  factory :ticket do
    account
    sequence(:title) { |n| "Ticket #{n}" }
    description { 'Sample ticket description' }
    status { :open }
  end
end
