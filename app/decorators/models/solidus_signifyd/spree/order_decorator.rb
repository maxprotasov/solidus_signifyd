module Models::SolidusSignifyd::Spree::OrderDecorator
  def self.prepended(base)
    base.include SolidusSignifyd::OrderConcerns
  end

  ::Spree::Order.prepend self
end
