class TransactionCategoriesController < ApplicationController
  include ActionView::RecordIdentifier

  def update
    @entry = Current.family.entries.transactions.find(params[:transaction_id])
    @entry.update!(entry_params)

    transaction = @entry.transaction

    set_category_rule_cta(transaction, changed: transaction.saved_change_to_category_id?)

    transaction.lock_saved_attributes!
    @entry.lock_saved_attributes!

    respond_to do |format|
      format.html { redirect_back_or_to transaction_path(@entry) }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            dom_id(transaction, :category_menu),
            partial: "categories/menu",
            locals: { transaction: transaction }
          ),
          *flash_notification_stream_items
        ]
      end
    end
  end

  private
    def entry_params
      params.require(:entry).permit(:entryable_type, entryable_attributes: [ :id, :category_id ])
    end
end
