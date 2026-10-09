class Transactions::CategorySuggestionsController < ApplicationController
  # Applies one or more category suggestions. Expects:
  #   suggestions[<transaction_id>] = <category_id>
  # A blank category_id for an entry means "dismiss" (no change).
  def create
    applied = 0

    suggestions_params.each do |transaction_id, category_id|
      next if category_id.blank?

      transaction = Current.family.transactions.find_by(id: transaction_id)
      category = Current.family.categories.find_by(id: category_id)
      next unless transaction && category

      transaction.update!(category: category)
      transaction.lock_attr!(:category_id)
      applied += 1
    end

    redirect_back_or_to transactions_path,
      notice: "#{applied} #{"transaction".pluralize(applied)} categorized"
  end

  private
    def suggestions_params
      params.fetch(:suggestions, {}).permit!.to_h
    end
end
