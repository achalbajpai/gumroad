# frozen_string_literal: true

require "spec_helper"

describe("Installment plan receipt functionality", type: :feature, js: true) do
  let(:product) { create(:product, :with_installment_plan, user: seller) }
  let(:seller) { create(:user) }
  let(:purchaser) { create(:user) }

  before do
    product.installment_plan.update!(number_of_installments: 3, recurrence: "monthly")

    allow(GlobalConfig).to receive(:dig)
      .with(:secure_external_id, default: {})
      .and_return({
                    primary_key_version: "1",
                    keys: { "1" => "a" * 32 }
                  })

    allow(Stripe::Balance).to receive(:retrieve).and_return(
      double("balance", available: [double("available_balance", amount: 100000, currency: "usd")])
    )
  end

  describe "first installment payment receipt" do
    let(:purchase) { create(:installment_plan_purchase, link: product, purchaser: purchaser) }

    before do
      create(:url_redirect, purchase: purchase)
      purchase.subscription.update!(charge_occurrence_count: 3)
    end

    it "shows installment numbering and new messaging" do
      visit receipt_purchase_url(purchase.external_id, host: "#{PROTOCOL}://#{DOMAIN}")
      expect(page).to have_content("Confirm your email address")

      fill_in "Email address:", with: purchase.email
      click_button "View receipt"

      expect(page).to have_content("Today's payment: 1 of 3")
      expect(page).to have_content("Upcoming payment: 2 of 3")

      expect(page).to have_content("Installment plan initiated on")
      expect(page).to have_content("Your final charge will be on")
      expect(page).to have_content("You can manage your payment settings")
      expect(page).to have_link("here")

      expect(page).not_to have_content("You will be charged once a month")
      expect(page).not_to have_content("subscription settings")
    end
  end

  describe "second installment payment receipt" do
    let(:original_purchase) { create(:installment_plan_purchase, link: product, purchaser: purchaser) }
    let(:second_purchase) { create(:recurring_installment_plan_purchase, link: product, subscription: original_purchase.subscription, purchaser: purchaser, created_at: original_purchase.created_at + 1.month) }

    before do
      create(:url_redirect, purchase: second_purchase)
      original_purchase.subscription.update!(charge_occurrence_count: 3)
    end

    it "shows correct numbering for second payment" do
      visit receipt_purchase_url(second_purchase.external_id, host: "#{PROTOCOL}://#{DOMAIN}")
      expect(page).to have_content("Confirm your email address")

      fill_in "Email address:", with: second_purchase.email
      click_button "View receipt"

      expect(page).to have_content("Today's payment: 2 of 3")
      expect(page).to have_content("Upcoming payment: 3 of 3")

      expect(page).to have_content("Installment plan initiated on")
      expect(page).to have_content("Your final charge will be on")
    end
  end

  describe "final installment payment receipt" do
    let(:subscription) { create(:subscription, link: product, user: purchaser, is_installment_plan: true, charge_occurrence_count: 3) }
    let(:original_purchase) { create(:installment_plan_purchase, link: product, purchaser: purchaser, price_cents: 10_00, subscription: subscription) }
    let(:second_purchase) { create(:recurring_installment_plan_purchase, link: product, subscription: subscription, purchaser: purchaser, price_cents: 10_00, created_at: original_purchase.created_at + 1.month) }
    let(:final_purchase) { create(:recurring_installment_plan_purchase, link: product, subscription: subscription, purchaser: purchaser, price_cents: 10_00, created_at: original_purchase.created_at + 2.months) }

    before do
      original_purchase
      second_purchase
      final_purchase

      create(:url_redirect, purchase: final_purchase)
      subscription.reload
    end

    it "shows final payment messaging" do
      visit receipt_purchase_url(final_purchase.external_id, host: "#{PROTOCOL}://#{DOMAIN}")
      expect(page).to have_content("Confirm your email address")

      fill_in "Email address:", with: final_purchase.email
      click_button "View receipt"

      expect(page).not_to have_content("Today's payment:")
      expect(page).not_to have_content("Upcoming payment")

      expect(page).to have_content("This is your final payment for your installment plan")
      expect(page).to have_content("You will not be charged again")
      expect(page).to have_content("Payment history:")
      expect(page).to have_content("Total amount paid:")
      expect(page).to have_content("$30")

      expect(page).not_to have_content("Your final charge will be on")
      expect(page).not_to have_content("You can manage your payment settings")
    end
  end
end
