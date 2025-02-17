require 'spec_helper'

module Spree::Api::SolidusSignifyd
  describe 'orders' do
    describe 'POST #update' do

      let(:order_number) { "19418" }
      let!(:order) { create(:completed_order_with_totals, number: order_number) }
      let!(:user) { create(:user) }
      let(:signifyd_sha) { 'sdGXFLSPZi5hTt8ZCVR9FeNMrsfmOblEIkpV2cCVLxM=' }

      let(:body) {
        {
          "analysisUrl" => "https://signifyd.com/v2/cases/1/analysis",
          "entriesUrl" => "https://signifyd.com/v2/cases/1/entries",
          "notesUrl" => "https://signifyd.com/v2/cases/1/notes",
          "orderUrl" => "https://signifyd.com/v2/cases/1/order",
          "status" => "DISMISSED",
          "uuid" => "709b9107-eda0-4cdd-bdac-a82f51a8a3f3",
          "headline" => "John Smith",
          "reviewDisposition" => nil,
          "associatedTeam" => {
            "teamName" => "anyTeam",
            "teamId" => 26,
            "getAutoDismiss" => true,
            "getTeamDismissalDays" => 2
            },
            "orderId" => order_number,
            "orderDate" => "2013-06-17T06:20:47-0700",
            "orderAmount" => 365.99,
            "createdAt" => "2013-11-05T14:23:26-0800",
            "updatedAt" => "2013-11-05T14:23:26-0800",
            "adjustedScore" => 262.6666666666667,
            "investigationId" => 1,
            "score" => 262.6666666666667,
            "caseId" => 1
          }
      }

      let(:headers) { { 'X-SIGNIFYD-SEC-HMAC-SHA256': signifyd_sha } }

      before do
        SolidusSignifyd::Config[:api_key] = 'ABCDE'
      end

      subject { post '/api/solidus_signifyd/orders', params: body.to_json, headers: headers }

      context "invalid sha" do
        let(:signifyd_sha) { "INVALID" }

        it "does not set signifyd_score" do
          subject
          order.reload
          expect(order.signifyd_order_score).to eq nil
        end

        it "responds with 401" do
          subject
          expect(response.code.to_i).to eq 401
        end
      end

      context "valid sha" do
        context "invalid order number" do
          before(:each) { order.destroy! }

          it "responds with a 404" do
            subject
            expect(response.code.to_i).to eq 404
          end
        end

        context "the order has been shipped" do

          it "returns without trying to act on the order" do
            allow_any_instance_of(Spree::Order).to receive(:shipped?).and_return(true)
            expect(SolidusSignifyd).not_to receive(:approve)
            expect_any_instance_of(Spree::Order).not_to receive(:cancel!)
            expect { subject }.not_to raise_error
            expect(response.status).to eq(200)
          end
        end

        context "the order has been canceled" do
          before(:each) { order.cancel! }

          it "returns without trying to act on the order" do
            expect(SolidusSignifyd).not_to receive(:approve)
            expect_any_instance_of(Spree::Order).not_to receive(:cancel!)
            expect { subject }.not_to raise_error
            expect(response.status).to eq(200)
          end
        end

        context "valid order number" do
          it "sets the order's signifyd_score" do
            subject
            order.reload
            expect(order.signifyd_order_score.score).to eq 262
          end

          it "sets the order's signifyd_case_id" do
            expect{ subject }.to change{ order.reload.signifyd_order_score.try!(:case_id) }.from(nil).to(1)
          end

          it "responds with 200" do
            subject
            expect(response.code.to_i).to eq 200
          end

          context "reviewDisposition is FRAUDULENT" do
            let(:signifyd_sha) { "ulHF48lbFO3M6UBMSi1tAroJWADeSggrr6V7ND8hBx0=" }

            before(:each) do
              @original_review_disposition = body['reviewDiposition']
              body['reviewDisposition'] = 'FRAUDULENT'
            end

            after(:each) { body['reviewDiposition'] = @original_review_disposition }

            it 'cancels the order' do
              expect_any_instance_of(Spree::Order).to receive(:cancel!)
              subject
            end
          end

          context "reviewDisposition is not FRAUDULENT" do
            context "the order has already been approved" do

              before(:each) { order.update_attribute(:approved_at, Time.now) }

              it "does not call approve" do
                expect(SolidusSignifyd).not_to receive(:approve)
                subject
              end
            end

            context "the order has not yet been approved" do
              context "the reviewDisposition is GOOD" do
                let(:signifyd_sha) { "wZIjgRQoDMWe0W4VoE5TJEoHf8ZcY9UeXY1lnGP+pfg=" }

                before(:each) do
                  @original_review_disposition = body['reviewDisposition']
                  body['reviewDisposition'] = 'GOOD'
                end

                after(:each) { body['reviewDisposition'] = @original_review_disposition }

                it "calls approve" do
                  expect(SolidusSignifyd).to receive(:approve).with(order: order)
                  subject
                end
              end

              context "the reviewDisposition is not GOOD" do
                it "does not call approve" do
                  expect(SolidusSignifyd).not_to receive(:approve)
                  subject
                end
              end

              context "the order is not risky" do
                let(:signifyd_sha) { "ZI7bSCavfy6pWogJZ7nq2LbLLojcfcy9kjF02WHO4nM=" }

                before(:each) do
                  @original_score = body['adjustedScore']
                  body['adjustedScore'] = SolidusSignifyd::Config[:signifyd_score_threshold] + 1
                end

                after(:each) { body['adjustedScore'] = @original_score }

                it "approves the order" do
                  expect(SolidusSignifyd).to receive(:approve).with(order: order)
                  subject
                end
              end

              context "the order is risky" do

                let(:signifyd_sha) { "YcEDVtPBAXcgQ9fJgBMSoBWy9CVpc6pnN6YzCbtD85E=" }

                before(:each) do
                  @original_score = body['adjustedScore']
                  body['adjustedScore'] = SolidusSignifyd::Config[:signifyd_score_threshold] - 1
                end

                after(:each) { body['adjustedScore'] = @original_score }

                it "does not approve the order" do
                  expect(SolidusSignifyd).not_to receive(:approve)
                  subject
                end
              end
            end
          end
        end
      end
    end
  end
end
