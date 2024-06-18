module Models::SpreeSignifyd::Spree::ShipmentDecorator
  def determine_state(order)
    return 'pending' if pending? && !order.approved?
    super(order)
  end

  ::Spree::Shipment.prepend self
end
