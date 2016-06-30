% ------- Main File ------ %
% Author : Bryce Ingersoll
% Institution: Brigham Young University, FLOW Lab
% Last Revised : 6/29/16
% ------------------------ %

clear; clc; close all;

%Add paths
addpath(genpath('.\Objective_Functions\'));
addpath(genpath('.\Constraints\'));
addpath(genpath('.\ColorPath\'));
addpath(genpath('.\Compare\'));
addpath(genpath('.\OptimalPathGuesses\'));
addpath(genpath('.\CalculateEnergyUse\'));


%-------global variables----------%
global xf; %final position
global x0; %current starting pointPath_bez
global step_max; %max step distance
global step_min; %minimum step distance
global t; %parameterization variable
global n_obs; %number of obstacles
global obs; %positions of obstacles
global obs_rad; %radius of obstacles
global turn_r; %minimum turn radius
global Pmid; %needed to match derivatives
global num_path; %number of segments optimized
global x_new;
global Dynamic_Obstacles;
global x_next; %used in multi_start function
global uav_ws; %UAV wing span
global start;
global initial; % to calculate d_l_min
initial = 1;
global uav_finite_size;
global rho f W span eo;
global summer cool copper parula_c;
global obj_grad cons_grad ag acg;

%------------Algorithm Options------------%
Dynamic_Obstacles = 0;

num_path = 3;              %Receding Horizon Approach (any number really, but 3 is standard)
ms_i = 3;                  %number of guesses for multi start (up to 8 for now, up to 3 for smart)
uav_finite_size = 1;       %input whether want to include UAV size

%Objective Function
optimize_energy_use = 0;    %changes which objective function is used
optimize_time =  0;         %if both are zero, then path length is optimized

max_func_evals = 100000;
max_iter = 50000;

% Plot Options
totl = 1;   %turn off tick labels
square_axes = 1;      %Square Axes
radar = 0;            %Plots UAV's limit of sight
linewidth = 3;        %Line width of traversed path segment
show_sp = 0;          %Plots P2 of Bezier curve
Show_Steps = 0;       %Needs to be turned on when Dynamic_Obstacles is turned on
show_end = 0;         %for calc_fig
compare_num_path = 0;
save_path = 1;        %save path data to use in compare
sds = 0;              %Allows a closer view of dynamic obstacle avoidance

create_video = 1;          %saves the solutions of the multistart approach at each iteration

% Gradient Calculation Options
obj_grad = 1;           %if this is 1 and below line is 0, complex step method will be used to calculate gradients
analytic_gradients = 1;
ag = analytic_gradients;

cons_grad = 1;          %if this is 1 and below line is 0, complex step method will be used to calculate gradients
analytic_constraint_gradients = 1;
acg = analytic_constraint_gradients;

%plot color options
speed_color = 1;         %use if you want color to represent speed
d_speed_color = 0;       %use if you want color to be discretized over path length
cb = 1;                  %color brightness
summer = 0;             % http://www.mathworks.com/help/matlab/ref/colormap.html#buq1hym
cool = 0;
copper = 0;
parula_c = 1;
color_bar = 1;
%----------------------------------------%

%-------------- one_path -----------------%

% -- obstacle fields used for opt_compare (rng 11-20) 40/4/3 -- %
%plan entire path
% to run this, first need to run using 3-4 num_path, save that path, and
% use that as your initial guess; also need to change number of num_path to
% match what was previously solved for
one_path = 0; %if this is on, need to set ms_i = 1
%planned vs. optimal paths
%rng(4); %49/4/3

%rng(11); %40/4/3 ; d = num_path = 13, t = num_path = 10, e = num_path = 11
%rng(12); %40/4/3 ; d = num_path = 14, t = num_path = 10, e = num_path = 11
%rng(13); %40/4/3 ; d = num_path = 14, t = num_path = 11, e = num_path = 12
%rng(14); %40/4/3 ; d = num_path = 14, t = num_path = 11, e = num_path = 12
%rng(15); %40/4/3 ; d = num_path = 14, t = num_path = 11, e = num_path = 13
%rng(16); %40/4/3 ; d = num_path = 13, t = num_path = 10, e = num_path = 12
%rng(17); %40/4/3 ; d = num_path = 13, t = num_path = 10, e = num_path = 11
%rng(18); %40/4/3 ; d = num_path = 13, t = num_path = 10, e = num_path = 12
%rng(19); %40/4/3 ; d = num_path = 13, t = num_path = 10, e = num_path = 12
%rng(20); %40/4/3 ; d = num_path = 14, t = num_path = 11, e = num_path = 12

if one_path == 1
    num_path = 11;
    ms_i = 1;
    get_bez_points = @rng20_t;
end
% ------------------------------------------------------------- %

l = 0;

%parameterization vector t
global delta_t;
t = linspace(0,1,10);
delta_t = t(2) - t(1);

%for plot_both function
%global Path_bez;

%----------------plane geometry/info----------------%
%UAV parameter values
rho = 1.225; %air density
f = .2;   %equivalent parasite area
W = 10; %weight of aircraft
span = .20;   %span
eo = 0.9; %Oswald's efficiency factor

turn_r = 5; %turn radius, m

%maximum/stall speed, m/s
max_speed = 15;
min_speed = 10;
if optimize_energy_use == 1
    min_speed = 10;
end

%transalte UAV information to fit with algorithm
step_max = max_speed; %/2;
step_min = min_speed; %/2;

%Wing span of UAV
if uav_finite_size == 1
    uav_ws = 1.0; %UAV wing span
else
    uav_ws = 0.001;
end

%starting/ending position of plane
x0 = [0,0];
xf = [100,100];
Bez_points = [];
%--------------------------------------------------%

%-------static obstacle information---------%
%rng(3); %50/4/3
rng(4);
n_obs = 50; %number of static obstacles
obs = rand(n_obs,2)*90+5; %obstacle locations
rng(4); %for partially random obstacle size
obs_rad = (4-uav_ws) +  rand(n_obs,1)*3; %obstacle radius
%-------------------------------------------%

%------dynamic obstacle information---------%
if Dynamic_Obstacles == 1
    
    global n_obsd obs_d_sp obs_d_v obs_d_s obs_d_cp;
    
    %choose 1-4 for cases (see function for description)
    [n_obsd, obs_d_sp, obs_d_s, obs_d_v]  = dyn_case(5);
    
    obs_d_s = obs_d_s-ones(n_obsd,1)*uav_ws; %size of obstacles, also used (5)
    obs_d_cp = obs_d_sp; %current position of obstacles
    obs_d_cp_hist(1,:,1) = obs_d_sp(1,:);
end
%-------------------------------------------%

% for make_video
if create_video == 1
    
    solution1 = [];
    solution2 = [];
    solution3 = [];
    solution4 = [];
    solution5 = [];
    
end

tic
%----------------- optimizer ---------- fmincon -----------------------%
%unused parts in fmincon
A = [];
b = [];
Aeq = [];
beq = [];
%lb = -10*ones(2*num_path,2);
%ub = 110*ones(2*num_path,2);
lb = [];
ub = [];

%Pmed initialization, used to match up derivatives between paths
Pmid = [-min_speed/2,-min_speed/2];
%Pmid = [-3,-3];

Path_bez = [];

path_start = [];

%initial guess(es)
start = 0;

xi = multi_start(ms_i);

%start
start = 1;

%x_new is not close to final position
x_new = zeros(2*num_path,2);

% note: each iteration of while loop represents some time step, in which
% UAV travels on path and dynamic obstacles move

%fmincon options
if obj_grad == 1 && cons_grad == 1
    options = optimoptions('fmincon','Algorithm','sqp','MaxFunEvals',max_func_evals,'MaxIter',max_iter,...
        'GradObj','on','GradCon','on','DerivativeCheck','off');
elseif obj_grad == 0 && cons_grad == 1
    options = optimoptions('fmincon','Algorithm','sqp','MaxFunEvals',max_func_evals,'MaxIter',max_iter,...
        'GradObj','off','GradCon','on','DerivativeCheck','off');
elseif obj_grad == 1 && cons_grad == 0
    options = optimoptions('fmincon','Algorithm','sqp','MaxFunEvals',max_func_evals,'MaxIter',max_iter,...
        'GradObj','on','GradCon','off','DerivativeCheck','off');
else
    options = optimoptions('fmincon','Algorithm','sqp','MaxFunEvals',max_func_evals,'MaxIter',max_iter,...
        'GradObj','off','GradCon','off');
end

while ( abs(x_new(2*num_path,1,1)-xf(1)) > 10^0 ) || ( abs(x_new(2*num_path,2,1)-xf(2)) > 10^0 )
    
    if one_path == 1
        break;
    end
    
    %record number of paths
    l = l + 1;
    
    
    for i = 1 : ms_i %multistart approach to find best solution
        
        %choose objective function
        if optimize_energy_use == 1
            
            
            [x_new(:,:,i),~,e(i,l)] = fmincon(@opt_e, xi(:,:,i) , A, b, Aeq, beq, lb, ub, @cons,options);
            
        elseif optimize_time == 1
            
            
            [x_new(:,:,i),~,e(i,l)] = fmincon(@opt_t, xi(:,:,i) , A, b, Aeq, beq, lb, ub, @cons,options);
            
        else
            
            
            [x_new(:,:,i),~,e(i,l)] = fmincon(@opt_d, xi(:,:,i) , A, b, Aeq, beq, lb, ub, @cons,options);
            
        end
        
    end
    
    for i = 1 : ms_i %calculate how good solutions are
        
        % For make_video
        if create_video == 1
            
            if i == 1
                solution1 = [solution1; x_new(:,:,i)];
            elseif i == 2
                solution2 = [solution2; x_new(:,:,i)];
            elseif i == 3
                solution3 = [solution3; x_new(:,:,i)];
            elseif i == 4
                solution4 = [solution4; x_new(:,:,i)];
            elseif i == 5
                solution5 = [solution5; x_new(:,:,i)];
            end
        end
        
        if optimize_energy_use == 1
            d_check(i) = opt_e(x_new(:,:,i));
            
        elseif optimize_time == 1
            d_check(i) = opt_t(x_new(:,:,i));
            
        else
            d_check(i) = opt_d(x_new(:,:,i));
            
        end
        
        %'remove' solutions that converged to an infeasible point
        
        if e(i,l) == -2
            
            d_check(i) = d_check(i)*10;
            
        end
        
        
    end
    
    for i = 1 : ms_i %choose best solution, use for next part
        
        if d_check(i) == min(d_check)
            
            x_next = x_new(:,:,i);
            
        end
    end
    
    %
    initial = 0;
    
    %switch to last optimizing function
    if abs(x_next(2*num_path,1)-xf (1)) < 10^-1  && abs(x_next(2*num_path,2)-xf (2)) < 10^-1
        break
    end
    
    %CHANGE
    if abs(x_next(2,1)-xf(1)) < min_speed*2 && abs(x_next(2,2)-xf(2)) < min_speed*2
        break
    end
    
    % makes the path of the UAV for this section
    for i = 1 : length(t)
        
        path_part(i,:) = (1-t(i))^2*x0(1,:) + 2*(1-t(i))*t(i)*x_next(1,:)+t(i)^2*x_next(2,:);
        
    end
    
    %make the planned path of the UAV
    if num_path > 1
        for j = 1 : (num_path-1)
            for i = 1 : length(t)
                path_planned(i+(j-1)*length(t),:) = (1-t(i))^2*x_next(2*j,:) + 2*(1-t(i))*t(i)*x_next(2*j+1,:)+t(i)^2*x_next(2*j+2,:);
            end
        end
    end
    
    %--------------------------------------- Plot -------------------------------------%
    if Show_Steps == 1
        figure(l);
        hold on
        
        if square_axes == 1
            axis square
        end
        
        if color_bar == 1
            colorbar('southoutside','Ticks',[0,0.20,0.4,0.6,0.8,1],'TickLabels',{'V_{min}, 10 m/s','11 m/s','12 m/s','13 m/s','14 m/s','V_{max},15 m/s'},'fontsize',10);
        end
        
        xlim([0 100]);
        ylim([0 100]);
        
        %pause
        
        if Dynamic_Obstacles == 0
            
            %-------------plot static obstacles-----------%
            for i = 1 : n_obs
                
                plot(obs(i,1),obs(i,2),'xk'); % static obstacles' centers
                x = obs(i,1) - obs_rad(i) : 0.001 : obs(i,1)+ obs_rad(i);
                y =  (obs_rad(i)^2 - (x - obs(i,1)).^2).^0.5 + obs(i,2); %top part of circle
                y1 = -(obs_rad(i)^2 - (x - obs(i,1)).^2).^0.5 + obs(i,2); %bottom part of circle
                
                plot(x,y,'k');
                plot(x,y1,'k');
                
            end
            
        end
        
        %pause
        
        %-------------------UAV Path------------------------%
        
        %plot path already traversed as a normal line
        
        
        if speed_color == 1
            
            num_segments = (length(path_part)+length(path_planned)+length(Path_bez))/length(t);
            num_bits = (length(path_part)+length(path_planned)+length(Path_bez))-1;
            
            segment_length = zeros(num_segments,1);
            bit_length = zeros(num_bits,1);
            
            segment = zeros(length(t),2,num_segments);
            bit = zeros(2,2,num_bits);
            
            %break up path into segments
            path_int = [Path_bez; path_part; path_planned];
            
            for i = 1 : num_segments
                
                segment(:,:,i) = path_int((i-1)*length(t)+1:length(t)*i,:);
                
            end
            
            %populate bit
            for i = 1 : num_bits
                
                bit(:,:,i) = path_int(i:i+1,:);
                
            end
            
            
            %calculate lengths of each segment
            for i = 1 : num_segments
                
                for j = 2 : length(t)
                    segment_length(i) = segment_length(i) + norm ( segment(j,:,i) - segment(j-1,:,i));
                end
                
                %check
                if segment_length(i) < step_min
                    segment_length(i) = step_min;
                end
                if segment_length(i) > step_max
                    segment_length(i) = step_max;
                end
                
                
            end
            
            %calculate lengths (velocity, since /delta_t) of each bit
            for i = 1 : num_bits
                bit_length(i) = norm( bit(2,:,i) - bit(1,:,i))/delta_t;
                
                %check
                if bit_length(i) < step_min
                    bit_length(i) = step_min;
                end
                if bit_length(i) > step_max
                    bit_length(i) = step_max;
                end
            end
            
            
            
            %compare lengths to speed
            
            for i = 1 : num_bits
                
                color_var_b(i) = (bit_length(i)-step_min)/(step_max-step_min);
                
            end
            
            
            %based on speed, change color
            for i = 1 : num_segments
                
                color_var(i) = (segment_length(i)-step_min)/(step_max-step_min);
                
            end
            
            
            c_r = color_r(color_var);
            c_g = color_g(color_var);
            c_b = color_b(color_var);
            
            %plot
            
            if d_speed_color == 1
                
                for i = 1 : num_bits
                    
                    
                    if i < length(t)*(l-1)
                        
                        %path already traveled
                        plot(bit(1:2,1,i),bit(1:2,2,i),'Color',[cb*(color_var_b(i)),cb*(1-color_var_b(i)),0]);
                    end
                    
                    if i >= length(t)*(l-1) && i < length(t)*l
                        
                        %plot path that UAV has just traversed as a bold line
                        plot(bit(1:2,1,i),bit(1:2,2,i),'Color',[cb*(color_var_b(i)),cb*(1-color_var_b(i)),0],'LineWidth',linewidth);
                        
                    else
                        
                        %plot path that UAV has planned as dashed line
                        if num_path > 1
                            plot(bit(1:2,1,i),bit(1:2,2,i),'--','Color',[cb*(color_var_b(i)),cb*(1-color_var_b(i)),0]);
                        end
                        
                    end
                    
                end
                
            else
                
                for i = 1 : num_segments
                    if i <= l-1
                        plot(segment(:,1,i),segment(:,2,i),'Color',[cb*c_r(i),cb*c_g(i),cb*c_b(i)]);
                    end
                    
                    if i > l-1 && i <= l
                        plot(segment(:,1,i),segment(:,2,i),'Color',[cb*c_r(i),cb*c_g(i),cb*c_b(i)],'LineWidth',linewidth);
                        
                    else
                        plot(segment(:,1,i),segment(:,2,i),'--','Color',[cb*c_r(i),cb*c_g(i),cb*c_b(i)]);
                    end
                end
                
            end
            
        else
            
            if l  == 1
                %nothing
            else
                plot(Path_bez(:,1),Path_bez(:,2),'Color',[0, cb, 0]);
            end
            
            %plot path that UAV has just traversed as a bold line
            plot(path_part(:,1),path_part(:,2),'Color',[0, cb, 0],'LineWidth',2);
            
            %plot path that UAV has planned as dashed line
            if num_path > 1
                plot(path_planned(:,1),path_planned(:,2),'--','Color',[0, 0.5, 0]);
            end
            
        end
        
        
        
        %         %plot location of UAV on traversed line as circle for each time step
        %         for i = 1 : length(t)
        %             plot(path_part(i,1),path_part(i,2),'go');
        %         end
        
        
        %plot radar of UAV
        if radar == 1
            
            rl = num_path*max_speed;
            
            
            x = x0(1) - rl : 0.001 : x0(1)+ rl;
            y =  (rl^2 - (x - x0(1)).^2).^0.5 + x0(2); %top part of circle
            y1 = -(rl^2 - (x - x0(1)).^2).^0.5 + x0(2); %bottom part of circle
            
            plot(x,y,'g');
            plot(x,y1,'g');
            
        end
        
        %plot UAV as circle at first and last time step
        
        if uav_finite_size == 1
            %plot where it is at start of time step
            x = path_part(1,1) - uav_ws : 0.001 : path_part(1,1)+ uav_ws;
            y =  (uav_ws^2 - (x - path_part(1,1)).^2).^0.5 + path_part(1,2); %top part of circle
            y1 = -(uav_ws^2 - (x - path_part(1,1)).^2).^0.5 + path_part(1,2); %bottom part of circle
            
            if speed_color == 1
                
                plot(x,y,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                plot(x,y1,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                
            else
                
                plot(x,y,'Color',[0, cb, 0]);
                plot(x,y1,'Color',[0, cb, 0]);
                
            end
            
            if show_sp == 1
                %plot where it is at start of time step
                x = x_next(1,1) - uav_ws : 0.001 : x_next(1,1)+ uav_ws;
                y =  (uav_ws^2 - (x - x_next(1,1)).^2).^0.5 + x_next(1,2); %top part of circle
                y1 = -(uav_ws^2 - (x - x_next(1,1)).^2).^0.5 + x_next(1,2); %bottom part of circle
                
                if speed_color == 1
                    
                    plot(x,y,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                    plot(x,y1,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                    
                else
                    
                    plot(x,y,'Color',[0, cb, 0]);
                    plot(x,y1,'Color',[0, cb, 0]);
                    
                end
                
                %plot where it is at start of time step
                x = x_next(3,1) - uav_ws : 0.001 : x_next(3,1)+ uav_ws;
                y =  (uav_ws^2 - (x - x_next(3,1)).^2).^0.5 + x_next(3,2); %top part of circle
                y1 = -(uav_ws^2 - (x - x_next(3,1)).^2).^0.5 + x_next(3,2); %bottom part of circle
                
                if speed_color == 1
                    
                    plot(x,y,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                    plot(x,y1,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                    
                else
                    
                    plot(x,y,'Color',[0, cb, 0]);
                    plot(x,y1,'Color',[0, cb, 0]);
                    
                end
                
                %plot where it is at start of time step
                x = x_next(5,1) - uav_ws : 0.001 : x_next(5,1)+ uav_ws;
                y =  (uav_ws^2 - (x - x_next(5,1)).^2).^0.5 + x_next(5,2); %top part of circle
                y1 = -(uav_ws^2 - (x - x_next(5,1)).^2).^0.5 + x_next(5,2); %bottom part of circle
                
                if speed_color == 1
                    
                    plot(x,y,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                    plot(x,y1,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                    
                else
                    
                    plot(x,y,'Color',[0, cb, 0]);
                    plot(x,y1,'Color',[0, cb, 0]);
                    
                end
                
            end
            
            %plot where it is at end of time step
            %plot where it is at start of time step
            x = path_part(length(t),1) - uav_ws : 0.001 : path_part(length(t),1)+ uav_ws;
            y =  (uav_ws^2 - (x - path_part(length(t),1)).^2).^0.5 + path_part(length(t),2); %top part of circle
            y1 = -(uav_ws^2 - (x - path_part(length(t),1)).^2).^0.5 + path_part(length(t),2); %bottom part of circle
            
            if speed_color == 1
                
                plot(x,y,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                plot(x,y1,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                
            else
                
                plot(x,y,'Color',[0, cb, 0]);
                plot(x,y1,'Color',[0, cb, 0]);
                
            end
        end
        
        %plot UAV as circle at last time step for future planned path
        if uav_finite_size == 1
            if num_path > 1
                for j = 1 : (num_path-1)
                    %plot where it is at end of time step
                    x = path_planned(j*length(t),1) - uav_ws : 0.001 : path_planned(j*length(t),1)+ uav_ws;
                    y =  (uav_ws^2 - (x - path_planned(j*length(t),1)).^2).^0.5 + path_planned(j*length(t),2); %top part of circle
                    y1 = -(uav_ws^2 - (x - path_planned(j*length(t),1)).^2).^0.5 + path_planned(j*length(t),2); %bottom part of circle
                    
                    if speed_color == 1
                        
                        plot(x,y,'Color',[cb*c_r(j+l), cb*c_g(j+l), cb*c_b(j+l)]);
                        plot(x,y1,'Color',[cb*c_r(j+l), cb*c_g(j+l), cb*c_b(j+l)]);
                        
                    else
                        
                        plot(x,y,'Color',[0, cb, 0]);
                        plot(x,y1,'Color',[0, cb, 0]);
                        
                    end
                end
            end
        end
        
        if Dynamic_Obstacles == 1
            
            if sds == 1 && (l == 7 || l == 8) 
                
                for i = 1 : length(t)
                    
                    %change figure number
                    figurenum = l*20 + i;
                    figure(figurenum);
                    hold on
                    %set plot boundary
                    xlim([40 60]);
                    ylim([40 60]);
                    timestep = l + t(i);
                    xlabel(['Time Step = ' num2str(timestep) ' s'])
                    %plot dynamic obstacles
                    
                    %plot small square at center of dynamic obstacles at each time step
                    for k = 1 : n_obsd
                        
                        plot(obs_d_v(k,1)*t(i) + obs_d_cp(k,1),obs_d_v(k,2)*t(i) + obs_d_cp(k,2),'s','Color',[0.5,0,0]);
                        
                        odh = obs_d_cp; % to make it easier to type
                        
                        x = obs_d_v(k,1)*t(i) + odh(k,1) - obs_d_s(k) : 0.001 : obs_d_v(k,1)*t(i) + odh(k,1)+ obs_d_s(k);
                        y =  (obs_d_s(k)^2 - (x - (obs_d_v(k,1)*t(i)+odh(k,1))).^2).^0.5 + odh(k,2) + obs_d_v(k,2)*t(i); %top part of circle
                        y1 = -(obs_d_s(k)^2 - (x - (obs_d_v(k,1)*t(i)+odh(k,1))).^2).^0.5 + odh(k,2) + obs_d_v(k,2)*t(i); %bottom part of circle
                        
                        plot(x,y,'Color',[0.5,0,0],'LineWidth',2);
                        plot(x,y1,'Color',[0.5,0,0],'LineWidth',2);
                    end    
                        %plot position of UAV
                        
                        x = segment(i,1,l) - uav_ws : 0.001 : segment(i,1,l)+ uav_ws;
                        y =  (uav_ws^2 - (x - segment(i,1,l)).^2).^0.5 + segment(i,2,l); %top part of circle
                        y1 = -(uav_ws^2 - (x - segment(i,1,l)).^2).^0.5 + segment(i,2,l); %bottom part of circle
                        plot(x,y,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                        plot(x,y1,'Color',[cb*c_r(l), cb*c_g(l), cb*c_b(l)]);
                    
                    hold off
                end
            end
            
            
            
            
            %plot small square at center of dynamic obstacles at each time step
            for k = 1 : n_obsd
                for i = 1 : length(t)
                    plot(obs_d_v(k,1)*t(i) + obs_d_cp(k,1),obs_d_v(k,2)*t(i) + obs_d_cp(k,2),'s','Color',[0.5,0,0]);
                end
            end
            %plot most recent previous placement of dynamic obstacles as bold circles
            for k = 1 : n_obsd
                
                plot(obs_d_cp(k,1),obs_d_cp(k,2),'s','Color',[0.5,0,0]); %plot center of obstacles
                odh = obs_d_cp; % to make it easier to type
                
                x = odh(k,1) - obs_d_s(k) : 0.001 : odh(k,1)+ obs_d_s(k);
                y =  (obs_d_s(k)^2 - (x - odh(k,1)).^2).^0.5 + odh(k,2); %top part of circle
                y1 = -(obs_d_s(k)^2 - (x - odh(k,1)).^2).^0.5 + odh(k,2); %bottom part of circle
                
                plot(x,y,'Color',[0.5,0,0],'LineWidth',2);
                plot(x,y1,'Color',[0.5,0,0],'LineWidth',2);
            end
            
            
            %plot current position of dynamic obstacles as dashed bold circles
            %dynamic obstacles position update
            for k = 1 : n_obsd
                obs_d_cp(k,:) = obs_d_v(k,:) + obs_d_cp(k,:);
            end
            
            for k = 1 : n_obsd
                
                plot(obs_d_cp(k,1),obs_d_cp(k,2),'s','Color',[0.5,0,0]); %plot center of obstacles
                odh = obs_d_cp; % to make it easier to type
                
                x = odh(k,1) - obs_d_s(k) : 0.001 : odh(k,1)+ obs_d_s(k);
                y =  (obs_d_s(k)^2 - (x - odh(k,1)).^2).^0.5 + odh(k,2); %top part of circle
                y1 = -(obs_d_s(k)^2 - (x - odh(k,1)).^2).^0.5 + odh(k,2); %bottom part of circle
                
                plot(x,y,'--','Color',[0.5,0,0]);
                plot(x,y1,'--','Color',[0.5,0,0]);
            end
            
        end
        
        %show end
        if show_end == 1
            plot([path_planned(length(t)*(num_path-1),1) 100],[path_planned(length(t)*(num_path-1),2) 100],'Color',[0 0 0],'LineWidth',2);
        end
        
        hold off
        
    end
    %----------------------------------------------------------%
    
    %record where start of each path is
    path_start = [path_start; path_part(1,:)];
    
    %continues the path which will be plotted
    Path_bez = [Path_bez; path_part];
    
    %set new starting point
    x0 = x_next(2,:);
    
    %set Pmid
    Pmid = x_next(1,:);
    
    %choose new guess for next iteration
    xi = multi_start(ms_i);
    
    %print current location
    x_next(2,:)
    
    Bez_points = [Bez_points; x_next(1:2,:)];
    
end %while


%-------------------------final optimization------------------%
%final guess
if one_path == 1
    x_guess_final = get_bez_points();
else
    x_guess_final = multi_start(ms_i);
end

%one path optimization for energy use
%if one_path == 1 && optimize_energy_use == 1
if optimize_energy_use == 1
    final_of = @final_eu;
else
    final_of = @final_dist;
end


for i = 1 : ms_i %multistart approach to find best solution
    
    options = optimoptions('fmincon','Algorithm','sqp','MaxFunEvals',10000,'MaxIter',100);
    %options = optimoptions('fmincon','Algorithm','sqp','MaxFunEvals',500000,'MaxIter',100000);
    x_final(:,:,i) = fmincon(final_of, x_guess_final(:,:,i) , A, b, Aeq, beq, lb, ub, @final_con,options);
    
end

% for compare_of function
if one_path == 1
    Bez_points = x_final;
end

for i = 1 : ms_i %calculate how good solutions are
    
    d_check(i) = final_dist(x_final(:,:,i));
    
end

for i = 1 : ms_i %choose best solution, use for next part
    
    if d_check(i) == min(d_check)
        
        x_fin = x_final(:,:,i);
        
    end
end


%--------------------Final Plot-------------------------------%

%------------add last segment of path to total-----------%
for j = 1 : num_path
    
    if j == 1
        for i = 1 : length(t)
            
            path_mid(i,:) = (1-t(i))^2*x0(1,:) + 2*(1-t(i))*t(i)*x_fin(1,:)+t(i)^2*x_fin(2,:);
            
        end
    else
        for i = 1 : length(t)
            
            path_mid(i,:) = (1-t(i))^2*x_fin(2*j-2,:) + 2*(1-t(i))*t(i)*x_fin(2*j-1,:)+t(i)^2*x_fin(2*j,:);
        end
    end
    
    path_start = [path_start; path_mid(1,:)];
    Path_bez = [Path_bez; path_mid];
end


    figure(l+1);
    hold on
    
    if square_axes == 1
        axis square
    end
    
    if totl == 1
        
        set(gca,'XTickLabel','')
        set(gca,'YTickLabel','')
        
    end
    
    %----------------plot UAV-------------------%
    if color_bar == 1
        colorbar('southoutside','Ticks',[0,0.20,0.4,0.6,0.8,1],'TickLabels',{'V_{min}, 10 m/s','11 m/s','12 m/s','13 m/s','14 m/s','V_{max},15 m/s'},'fontsize',14);
    end
    if speed_color == 1
        
        num_segments = length(Path_bez)/length(t);
        num_bits = length(Path_bez)-1;
        
        segment_length = zeros(num_segments,1);
        bit_length = zeros(num_bits,1);
        
        segment = zeros(length(t),2,num_segments);
        bit = zeros(2,2,num_bits);
        
        %break up path into segments
        for i = 1 : num_segments
            
            segment(:,:,i) = Path_bez((i-1)*length(t)+1:length(t)*i,:);
            
        end
        
        %populate bit
        for i = 1 : num_bits
            
            bit(:,:,i) = Path_bez(i:i+1,:);
            
        end
        
        
        %calculate lengths of each segment
        for i = 1 : num_segments
            
            for j = 2 : length(t)
                segment_length(i) = segment_length(i) + norm ( segment(j,:,i) - segment(j-1,:,i));
            end
            
            %check
            if segment_length(i) < step_min
                segment_length(i) = step_min;
            end
            if segment_length(i) > step_max
                segment_length(i) = step_max;
            end
            
            
        end
        
        %calculate lengths (velocity, since /delta_t) of each bit
        for i = 1 : num_bits
            bit_length(i) = norm( bit(2,:,i) - bit(1,:,i))/delta_t;
            
            %check
            if bit_length(i) < step_min
                bit_length(i) = step_min;
            end
            if bit_length(i) > step_max
                bit_length(i) = step_max;
            end
        end
        
        
        
        %compare lengths to speed
        
        for i = 1 : num_bits
            
            color_var_b(i) = (bit_length(i)-step_min)/(step_max-step_min);
            
        end
        
        r_color_var_b = zeros(num_bits,1);
        g_color_var_b = zeros(num_bits,1);
        b_color_var_b = zeros(num_bits,1);
        
        %based on speed, change color
        for i = 1 : num_segments
            
            color_var(i) = (segment_length(i)-step_min)/(step_max-step_min);
            
        end
        
        
        
        c_r = color_r(color_var);
        c_g = color_g(color_var);
        c_b = color_b(color_var);
        
        
        %plot
        
        if d_speed_color == 1
            
            for i = 1 : num_bits
                
                plot(bit(1:2,1,i),bit(1:2,2,i),'Color',[cb*(color_var_b(i)),cb*(1-color_var_b(i)),0]);
                
            end
            
        else
            
            for i = 1 : num_segments
                
                plot(segment(:,1,i),segment(:,2,i),'Color',[cb*c_r(i), cb*c_g(i), cb*c_b(i)]);
                
            end
            
        end
        
        
        
    else
        
        plot(Path_bez(:,1),Path_bez(:,2),'Color',[0, cb, 0]); %plots path of UAV
        
    end
    
    if uav_finite_size == 0
        for i = 1 : length(path_start)
            
            if speed_color == 1
                
                plot(path_start(i,1),path_start(i,2),'o','Color',[cb*(color_var_b(i)),cb*(1-color_var_b(i)),0]);
                
            else
                
                plot(path_start(i,1),path_start(i,2),'og');
                
            end
            
        end
    end
    
    if uav_finite_size == 1
        for i = 1 : length(path_start)
            
            if speed_color == 1
                
                x = path_start(i,1) - uav_ws : 0.001 : path_start(i,1)+ uav_ws;
                y =  (uav_ws^2 - (x - path_start(i,1)).^2).^0.5 + path_start(i,2); %top part of circle
                y1 = -(uav_ws^2 - (x - path_start(i,1)).^2).^0.5 + path_start(i,2); %bottom part of circle
                
                plot(x,y,'Color',[cb*c_r(i), cb*c_g(i), cb*c_b(i)]);
                plot(x,y1,'Color',[cb*c_r(i), cb*c_g(i), cb*c_b(i)]);
                
            else
                
                x = path_start(i,1) - uav_ws : 0.001 : path_start(i,1)+ uav_ws;
                y =  (uav_ws^2 - (x - path_start(i,1)).^2).^0.5 + path_start(i,2); %top part of circle
                y1 = -(uav_ws^2 - (x - path_start(i,1)).^2).^0.5 + path_start(i,2); %bottom part of circle
                
                plot(x,y,'Color',[0, cb, 0]);
                plot(x,y1,'Color',[0, cb, 0]);
            end
        end
    end
    
    
    %-----------------------------------------%
    
    for i = 1 : n_obs %-------- static obstacles ----------%
        
        
        plot(obs(i,1),obs(i,2),'xk'); % staic obstacles' centers
        x = obs(i,1) - obs_rad(i) : 0.001 : obs(i,1)+ obs_rad(i);
        y =  (obs_rad(i)^2 - (x - obs(i,1)).^2).^0.5 + obs(i,2); %top part of circle
        y1 = -(obs_rad(i)^2 - (x - obs(i,1)).^2).^0.5 + obs(i,2); %bottom part of circle
        
        plot(x,y,'k');
        plot(x,y1,'k');
        
        
    end  %--------------------------------------%
    
    xlim([0 100]);
    ylim([0 100]);
    hold off


%compare paths created using various number of look ahead paths
if compare_num_path == 1
    
    if num_path == 1
        save('.\Compare\path_1.txt','Path_bez','-ascii');
        save('.\Compare\start_1.txt','path_start','-ascii');
    elseif num_path == 2
        save('.\Compare\path_2.txt','Path_bez','-ascii');
        save('.\Compare\start_2.txt','path_start','-ascii');
    elseif num_path == 3
        save('.\Compare\path_3.txt','Path_bez','-ascii');
        save('.\Compare\start_3.txt','path_start','-ascii');
    elseif num_path == 4
        save('.\Compare\path_4.txt','Path_bez','-ascii');
        save('.\Compare\start_4.txt','path_start','-ascii');
    elseif num_path == 5
        save('.\Compare\path_5.txt','Path_bez','-ascii');
        save('.\Compare\start_5.txt','path_start','-ascii');
    elseif num_path == 6
        save('.\Compare\path_6.txt','Path_bez','-ascii');
        save('.\Compare\start_6.txt','path_start','-ascii');
    end
    
end

%save path info to use in 'compare file'
if save_path == 1
    
    if optimize_energy_use == 1
        if one_path == 1
            save('.\Compare\path_e_opt.txt','Path_bez','-ascii');
            save('.\Compare\start_e_opt.txt','path_start','-ascii');
            
        else
            save('.\Compare\path_e.txt','Path_bez','-ascii');
            save('.\Compare\start_e.txt','path_start','-ascii');
        end
    elseif optimize_time == 1
        if one_path == 1
            save('.\Compare\path_t_opt.txt','Path_bez','-ascii');
            save('.\Compare\start_t_opt.txt','path_start','-ascii');
            
        else
            save('.\Compare\path_t.txt','Path_bez','-ascii');
            save('.\Compare\start_t.txt','path_start','-ascii');
        end
    else
        if one_path == 1
            save('.\Compare\path_d_opt.txt','Path_bez','-ascii');
            save('.\Compare\start_d_opt.txt','path_start','-ascii');
            
        else
            save('.\Compare\path_d.txt','Path_bez','-ascii');
            save('.\Compare\start_d.txt','path_start','-ascii');
        end
        
        
        
    end
end

%save guess to start one_path
if one_path == 0
    Bez_points = [Bez_points; x_fin];
    
    if optimize_time == 1
        
        %attempt to see if it can plan path with one less (note -2) segment
        %Bez_points_t = Bez_points(1:length(Bez_points)-2,:);
        
    end
    
end

%output of compare (energy, distance, time)
[td, tt, te] = compare_of(Bez_points,optimize_energy_use,optimize_time);

toc