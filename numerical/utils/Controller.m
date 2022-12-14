classdef Controller < handle
    %CONTROLLER this class stores the controller parameters and keeps a
    %record of the current controller states; crucially, the member
    %function "get_control(...)" will return the control signal given the
    %controller states as well as the system state.

    properties
        guidance_phase  % search phase or track phase?
        sampling_time  % in seconds
    end

    methods
        function obj = Controller(sampling_time)
            obj.guidance_phase = GuidancePhase.Search;
            obj.sampling_time = sampling_time;
        end

        function control = constrain_control(obj, control, params)
            for ii = 1:params.num_drones
                if norm(control(ii, :)) > 1
                    % if the norm of the desired control is > 1, normalize each row
                    control(ii, :) = control(ii,:) / norm(control(ii,:));
                end
            end
        end

        function out = get_control(obj, sample, state, system_parameters, laser_intensity)
            % out = matrix of size (NUM_DRONES x 3) where columns are
            % (xdot, ydot, zdot)
            out = zeros(system_parameters.num_drones, 3);

            % Boilerplate for persistent variables (marginally faster than
            % using member variables and making the Controller class
            % subclass of handle, according to qualitative testing).
            persistent u_old_z e_old_z u_old_x e_old_x u_old_y e_old_y;
            if isempty(u_old_z)
                u_old_z = zeros(1, system_parameters.num_drones);
            end

            if isempty(e_old_z)
                e_old_z = zeros(1, system_parameters.num_drones);
            end

            if isempty(u_old_x)
                u_old_x = zeros(1, system_parameters.num_drones);
            end

            if isempty(e_old_x)
                e_old_x = zeros(1, system_parameters.num_drones);
            end

            if isempty(u_old_y)
                u_old_y = zeros(1, system_parameters.num_drones);
            end

            if isempty(e_old_y)
                e_old_y = zeros(1, system_parameters.num_drones);
            end

            if obj.guidance_phase == GuidancePhase.Search
                % Subdivide the arena into "num_dronnes" equally sized 
                % chunks. Have each drone conduct a lawnmower search over 
                % their respective chunk at the max height possible.
                [~, drones_state, ~] = state.get_state();
                T = obj.sampling_time;
                
                % Compute z-axis position control
                u_left_vec = -[0.506449719108587];
                e_left_vec = [95.871889860291304 -89.515570805993178];
                for ii = 1:system_parameters.num_drones
                    % for each drone, grab the drone's current 'z' position
                    z = drones_state(ii, 5);

                    % drone "ii"s desired z position
                    z_des = 10; % for now this is fixed... modify later

                    % apply pure discrete-time control law
                    u = (u_left_vec * u_old_z(:, ii) + e_left_vec * [(z_des - z); e_old_z(:,ii)]);
                    e_old_z(:, ii) = (z_des - z);
                    u_old_z(:, ii) = u;
                    out(ii, 3) = u;
                end

                % Compute xy-plane position control
                for ii = 1:system_parameters.num_drones
                    % for each drone, grab the drone's current 'x', 'y',
                    % and 'z' positions
                    x = state.drones_state(ii, 1);
                    y = state.drones_state(ii, 3);
                    z = state.drones_state(ii, 5);

                    % Compute the desired reference trajectory
                    % (parameterized by 'k') as a function of the arena
                    % size and drone FOV (possibly as well as other system
                    % parameters like laser intensity clutter, laser
                    % intensity Gaussian noise, expected depth of ROVs etc)
                    arena_width = double(system_parameters.grid_cols * system_parameters.grid_unit_length);
                    arena_length = double(system_parameters.grid_rows * system_parameters.grid_unit_length);
                    x_des_0 = double(ii - 1) * (arena_width / double(system_parameters.num_drones)) + arena_width / double(system_parameters.num_drones) / 2 - arena_width / 2;
                    x_des_amplitude = max([(arena_width / double(system_parameters.num_drones) - 2 * z * tan(system_parameters.drone_fov)) / 2, 0]);
                    y_des_amplitude = max([(arena_length - 2 * z * tan(system_parameters.drone_fov)) / 2, 0]);
                    omega_x = 1.0; %2.0 ... one drone = 1.5
                    x_des = x_des_0 + x_des_amplitude * cos(omega_x * sample * obj.sampling_time); % 1.5
                    omega_y = 0.15;%1/(2 * arena_length / (4 * z * tan(system_parameters.drone_fov)) * omega_x);
                    y_des = y_des_amplitude * sin(omega_y * sample * obj.sampling_time + double(ii - 1) * deg2rad(120)); % 0.5

                    % Execute waypoint tracking for y position
                    u = (u_left_vec * u_old_y(:, ii) + e_left_vec * [(y_des - y); e_old_y(:,ii)]);
                    e_old_y(:, ii) = (y_des - y);
                    u_old_y(:, ii) = u;
                    out(ii, 2) = u;

                    % Execute waypoint tracking for x position
                    u = (u_left_vec * u_old_x(:, ii) + e_left_vec * [(x_des - x); e_old_x(:,ii)]);
                    e_old_x(:, ii) = (x_des - x);
                    u_old_x(:, ii) = u;
                    out(ii, 1) = u;
                end
            elseif obj.guidance_phase == GuidancePhase.Track
                % if we are in track mode, then turn start estimating the
                % state

                % determine the index of the drone(s) currently "seeing"
                % the laser signal
                detectors = [];
                for ii = 1:system_parameters.num_drones 
                    if laser_intensity(ii) > 2.58 * 0.0025
                        detectors(end+1) = ii;
                    end
                end

                if isempty(detectors)
                    % if the controller was in "track" phase upon entering
                    % this function, but we are not detecting anything,
                    % then switch to search phase and get the control from
                    % that.
                    disp("tracking off") % just for debugging purposes
                    obj.guidance_phase = GuidancePhase.Search;
                    out = obj.get_control(sample, state, system_parameters, laser_intensity);
                else
                    % if the controller is in "track" phase, and we can
                    % still "see" the ROV, then initiate tracking guidance
                    % sequence.

                    obj.guidance_phase = GuidancePhase.Search;
                    out = obj.get_control(sample, state, system_parameters, laser_intensity);
                    obj.guidance_phase = GuidancePhase.Track;
                end
            end

            % saturate the control effort used by each drone if the control
            % signals exceed the bound
            out = obj.constrain_control(out, system_parameters);
        end
    end
end