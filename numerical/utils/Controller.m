classdef Controller
    %CONTROLLER Summary of this class goes here
    %   Detailed explanation goes here

    properties
        guidance_phase  % search track or track phase
    end

    methods
        function obj = Controller()
            obj.guidance_phase = GuidancePhase.Search;
        end

        function control = constrain_control(obj, control, params)
            for ii = 1:params.num_drones
                if norm(control(ii, :)) > 1
                    % if the norm of the desired control is > 1, normalize each row
                    control(ii,:) = control(ii,:) / norm(control(ii,:));
                end
            end
        end

        function out = get_control(obj, state, params)
            % out = matrix of size (NUM_DRONES x 3) where columns are
            % (xdot, ydot, zdot)
            out = zeros(params.num_drones, 3);

            if obj.guidance_phase == GuidancePhase.Search
                % apply the entropy based search approach here...

                % switch when we detect a target above a threshold
            elseif obj.guidance_phase == GuidancePhase.Track
                % "elseif" unnecessary since only other is "track", but for
                % clarity...

                

                % apply "triangulation" approach...

            end

            out = obj.constrain_control(out, params);
        end
    end
end