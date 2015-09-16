module Bosh::Director::DeploymentPlan
  class NetworkPlan
    def initialize(attrs)
      @reservation = attrs.fetch(:reservation)
      @obsolete = attrs.fetch(:obsolete, false)
      @existing = attrs.fetch(:existing, false)
    end

    attr_reader :reservation

    def obsolete?
      !!@obsolete
    end

    def existing?
      !!@existing
    end
  end

  class NetworkPlanner
    def initialize(logger)
      @logger = logger
    end

    def plan_ips(desired_reservations, existing_reservations)
      unplaced_existing_reservations = Set.new(existing_reservations)
      existing_network_plans = []

      existing_reservations.each do |existing_reservation|
        desired_reservation = desired_reservations.find { |ip| ip.network == existing_reservation.network }

        if desired_reservation && existing_reservation.reserved?
          @logger.debug("Existing reservation #{existing_reservation} is still needed by #{desired_reservation}")

          if both_are_dynamic_reservations(existing_reservation, desired_reservation) ||
            both_are_static_reservations_with_same_ip(existing_reservation, desired_reservation)
            existing_network_plans << NetworkPlan.new(reservation: existing_reservation, existing: true)
            @logger.debug("Found matching existing reservation #{existing_reservation} for '#{desired_reservation}'")
            unplaced_existing_reservations.delete(existing_reservation)
            desired_reservation.resolve_ip(existing_reservation.ip) if desired_reservation.dynamic?
            desired_reservation.mark_reserved
          end
        else
          @logger.debug("Unneeded reservation #{existing_reservation}")
        end
      end

      obsolete_network_plans = unplaced_existing_reservations.map do |reservation|
        NetworkPlan.new(reservation: reservation, obsolete: true)
      end

      desired_network_plans = desired_reservations.map do |reservation|
        NetworkPlan.new(reservation: reservation)
      end

      existing_network_plans + desired_network_plans + obsolete_network_plans
    end

    private

    def both_are_dynamic_reservations(existing_reservation, reservation)
      existing_reservation.type == reservation.type &&
        reservation.dynamic?
    end

    def both_are_static_reservations_with_same_ip(existing_reservation, reservation)
      existing_reservation.type == reservation.type &&
        reservation.static? &&
        reservation.ip == existing_reservation.ip
    end
  end
end