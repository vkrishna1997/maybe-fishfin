class Transactions::CategorySuggestionsController < ApplicationController
  # Applies one or more category suggestions. Expects:
  #   suggestions[<transaction_id>] = <category_id>
  # A blank category_id for an entry means "dismiss" (no change).
  def create
    applied = 0

    submitted_suggestions.each do |transaction_id, category_id|
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
    # A map of { transaction_id => category_id } with dynamic keys, so each pair
    # is read directly rather than mass-assigned.
    def submitted_suggestions
      raw = params[:suggestions]
      return {} unless raw.respond_to?(:each_pair)

      raw.each_pair.map { |transaction_id, category_id| [ transaction_id.to_s, category_id.to_s ] }
    end
end
