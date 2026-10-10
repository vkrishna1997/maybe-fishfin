class Transactions::BulkUpdatesController < ApplicationController
  def new
  end

  def create
    entries = Current.family.entries.where(id: bulk_update_params[:entry_ids])

    cta_transaction = category_rule_cta_candidate(entries)

    updated = entries.bulk_update!(bulk_update_params)

    set_category_rule_cta(cta_transaction.reload, changed: true) if cta_transaction

    redirect_back_or_to transactions_path, notice: "#{updated} transactions updated"
  end

  private
    # When exactly one transaction's category is being changed, returns that
    # transaction so we can offer a "create a rule?" prompt after the update.
    # bulk_update! locks saved attributes, so the change must be detected first.
    def category_rule_cta_candidate(entries)
      new_category_id = bulk_update_params[:category_id]
      return nil if new_category_id.blank?
      return nil unless entries.count == 1

      transaction = entries.first.transaction
      return nil if transaction.category_id == new_category_id

      transaction
    end

    def bulk_update_params
      params.require(:bulk_update)
            .permit(:date, :notes, :category_id, :merchant_id, entry_ids: [], tag_ids: [])
    end
end
