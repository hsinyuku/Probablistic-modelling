// applicable to data on cases by date of onset
// ------------------
functions { // write functions that can be used later on
  // forcing function ----
  real switch_eta(real t, real t1, real eta, real nu, real xi) {
    return(eta+(1-eta)/(1+exp(xi*(t-t1-nu))));
  }
  // compartmental model ----
  real[] SEIR(
    // arguments to the ODE-function
    real t,
    real[] y,
    real[] theta, // theta is a list of all the parameters
    real[] x_r,   // list of all real-valued fixed paremeters
    int[] x_i     // list of all integer-valued fixed paremeters (only K)
  ) {
    // unpacking the parameters to the ODE from the initial arguments
    int K = x_i[1]; // gender, should be 2
    
    real tswitch = x_r[1]; // time of control measures
    real dydt[(6*K)];      // SEPIAR (ignoring R) then C 
    real nI;               // total infectious

    real beta;            // transmission rate
    real eta;             // reduction in transmission rate after quarantine
    real xi;              // slope of quarantine implementation
    real nu;              // shift of quarantine implementation
    real tau_1;           // infection to preclinical
    real tau_2;           // preclinical to symptoms (tau_1+tau_2 = incubation)
    real q_P;             // contribution of presymptomatics to transmission
    real gt;              // generation time
    real mu;              // infectious duration for symptomatics
    real psi;             // probability of symptoms
    real kappa;           // reduced transmissibility of preclinical and asymptomatics
    real p_tswitch;       // switch function
    real contact[K*K];    // contact matrix, first K values, corresponds to number 
                          // of contact between age class 1 and other classes, etc
    real f_inf[K];        // force of infection
    real init[K*2];       // initial values
    real gender_dist[K];  // age distribution of the general population
    real pi;              // number of cases at t0
    
    // Estimated parameters
    beta = theta[1];
    eta  = theta[2];
    xi   = theta[3];
    nu   = theta[4];
    pi   = theta[5];
    psi  = theta[6];

    // Fixed real valued parameters
    tau_1 = x_r[2];
    tau_2 = x_r[3];
    q_P   = x_r[4];
    gt    = x_r[5];
    
    // Composite parameters
    mu = (1-q_P)/(gt-1/tau_1-1/tau_2);
    kappa = (q_P*tau_2*psi)/((1-q_P)*mu-(1-psi)*q_P*tau_2);
    
    // Contact matrix
    contact = x_r[6:(5+K*K)];
    
    // Initial conditions
    for(k in 1:K){
      gender_dist[k] = x_r[5+K*K + k];
      init[k] = gender_dist[k] * (1-pi); // Population percentage in S
      init[K+k] = gender_dist[k] * pi; // Population percentage in E
    }
    
    // Total number of infectious people
    p_tswitch = switch_eta(t,tswitch,eta,nu,xi);
    
    /*
      Force of infection by age classes: 
      beta * p_tswitch * sum((number of infected people by age + 
      + kappa*number of preclinical by age + kappa*number of asympto) / 
      (total number of people by age) * (number of contact by age))
    */
    for(k in 1:K) {
      f_inf[k] = beta * p_tswitch * sum((to_vector(y[(3*K+1):(4*K)]) + 
        kappa*to_vector(y[(2*K+1):(3*K)]) + 
        kappa*to_vector(y[(4*K+1):(5*K)]))./ to_vector(gender_dist) .*
        to_vector(contact[(K*(k-1)+1):(k*K)])); 
    }

    // Compartments
    for (k in 1:K) {
      // S: susceptible
      dydt[k] = - f_inf[k] * (y[k]+init[k]); 
      // E: incubating (not yet infectious)
      dydt[K+k] = f_inf[k] * (y[k]+init[k]) - tau_1 * (y[K+k]+init[K+k]);
      // P: presymptomatic (incubating and infectious)
      dydt[2*K+k] = tau_1 * (y[K+k]+init[K+k]) - tau_2 * y[2*K+k];
      // I: symptomatic
      dydt[3*K+k] = psi * tau_2 * y[2*K+k] - mu * y[3*K+k];
      // A: asymptomatic
      dydt[4*K+k] = (1-psi) * tau_2 * y[2*K+k] - mu * y[4*K+k];
      // C: cumulative number of infections by date of disease onset
      dydt[5*K+k] = psi * tau_2 * y[2*K+k];
    }
    return(dydt);
  }
  // 
}

// ------------------
data {
  // |_ Structure ----
  int K;                 // number of age classes
  vector[K] gender_dist; // age distribution of the population
  int pop_t;             // total population
  real tswitch;          // time of introduction of control measures
  // |_ Controls ----
  int  S; // 
  real ts[S]; // time bins
  int  inference; // 0: simulating from priors; 1: fit to data
  int  doprint;
  // |_ Data to fit ----
  int incidence_cases[S]; // overal incidence for W weeks
  int incidence_deaths[S]; // overal incidence for W weeks
  int genderdistr_cases[K]; // number of cases at tmax for the K age classes
  int genderdistr_deaths[K]; // mortality at tmax for the K age classes
  // |_ Parameters for Priors ----
  real p_beta[2];
  real p_eta[2];
  real p_pi[2];
  real p_epsilon[2];
  real p_rho[2];
  real p_phi;
  real p_xi[2];
  real p_nu;
  real p_psi[2];
  // |_ Fixed values ----
  real contact[K*K]; // contact matrix
  real p_q_P; // proportion of transmission that is caused by presymptomatics
  real p_generation_time; 
  real tau_1;
  real tau_2;
  // |_ Fixed corrections ----
  real p_underreport_deaths; // correction for deaths reported later
  real p_underreport_cases; // correction for cases reported later
  // |_ Fixed delays ----
  int G;
  real p_gamma[G]; // from onset to death
}


// ------------------
transformed data {
  real q_P = p_q_P;
  real gt = p_generation_time;
  real x_r[5+K*K+K]; // 5 parameters + K*K contact matrix parameters + K age_dist parameters
  int  x_i[1] = {K};
  real init[K*6] = rep_array(0.0, K*6); // initial values
  x_r[1] = tswitch;
  x_r[2] = tau_1;
  x_r[3] = tau_2;
  x_r[4] = q_P;
  x_r[5] = gt;
  x_r[6:(5+K*K)] = contact;
  for(k in 1:K) {
    x_r[5+K*K+k] = gender_dist[k];
  }
}


// ------------------
parameters{
  real<lower=0,upper=1> beta; // base transmission rate
  real<lower=0,upper=1> eta; // reduction in transmission rate after quarantine measures
  vector<lower=0,upper=1> [K] epsilon; // age-dependent mortality probability
  vector<lower=0,upper=1> [K] raw_rho; // age-dependent reporting probability
  real<lower=0, upper=1> pi; // number of cases at t0
  real<lower=0> phi[2]; // variance parameters
  real<lower=0,upper=1> xi_raw; // slope of quarantine implementation
  real<lower=0> nu; // shift of quarantine implementation
  real<lower=0,upper=1> psi; // proportion of symptomatics
}

// ------------------
transformed parameters {
  vector[K] rho;
  real xi = xi_raw+0.5;
  // change of format for integrate_ode_rk45 - WHAT EXACTLY DOES THIS DO?
  real theta[6]; // vector of parameters
  real y[S,K*6]; // raw ODE output
  vector[K] comp_C[S+G];
  vector[K] comp_diffC[S+G];
  vector[K] comp_M[S+G];
  vector[K] comp_diffM[S+G];
  // outcomes - WHAT EXACTLY DOES THIS DO?
  vector[S] output_incidence_cases; // overall case incidence by day
  vector[S] output_incidence_deaths; // overal mortality incidence by day 
  simplex[K] output_genderdistr_cases; // final age distribution of cases
  simplex[K] output_genderdistr_deaths; // final age distribution of deaths
  
  // transformed parameters - WHAT EXACTLY DOES THIS DO?
  for(i in 1:K){
    rho[i] = raw_rho[i];
  }
  // change of format for integrate_ode_rk45
  theta[1:6] = {beta,eta,xi,nu,pi,psi};
  
  //|_ ODE solver ----
  y = integrate_ode_rk45( // simulate data on the current state of theta
    SEIR,  // ODE function
    init,  // initial states
    0,    // t0
    ts,    // evaluation dates (ts)
    theta, // parameters
    x_r,   // real data
    x_i,   // integer data
    1.0E-10, 1.0E-10, 1.0E3); // tolerances and maximum steps
  // extract and format ODE results (1.0E-9 correction to avoid negative values due to unprecise estimates of zeros as tolerance is 1.0E-10)
  for(i in 1:S) {
    comp_C[i] = (to_vector(y[i,(5*K+1):(6*K)]) + 1.0E-9) * pop_t;
      // C_k(t): number of presymptomatic people at day i in 1:S
    comp_diffC[i] = i==1 ? comp_C[i,] : 1.0E-9*pop_t + comp_C[i,] - comp_C[i-1,];
      // Delta C_{k,t}
      // number of new symptomatic infections per day of symptom onset by age group
  }
  //|_ (Cum.) incidences after S ----
  for(g in 1:G) {
    comp_C[S+g] = comp_C[S];
    comp_diffC[S+g] = rep_vector(1.0E-9,K);
  }
  //|_ Mortality ----
  for(i in 1:(S+G)) comp_diffM[i] = rep_vector(1.0E-9,K);
  for(i in 1:S) for(g in 1:G) comp_diffM[i+g] += comp_diffC[i] .* epsilon * p_gamma[g];
  for(i in 1:(S+G)) for(k in 1:K) comp_M[i,k] = sum(comp_diffM[1:i,k]);
  
  // Compute outcomes
  for(i in 1:S){
    output_incidence_cases[i] = sum(comp_diffC[i].*rho)*p_underreport_cases;
      // R_t: total number of new reported infections per day of symptom onset
      // not a percentage, but a count
    output_incidence_deaths[i] = sum(comp_diffM[i])*p_underreport_deaths;
  }
  output_genderdistr_cases = (comp_C[S,].*rho) ./ sum(comp_C[S,].*rho);
    // D_k^{cases}: age distribution of all reported cases over the modeled
    // period; not a percentage, but a count
  output_genderdistr_deaths = (comp_M[S,]) ./ sum(comp_M[S,]);
}


// ------------------
model {
  //|_ Prior Distributions ----
  beta   ~ beta(p_beta[1],p_beta[2]);
  eta    ~ beta(p_eta[1],p_eta[2]);
  for(k in 1:K) epsilon[k] ~ beta(p_epsilon[1],p_epsilon[2]);
  for(k in 1:(K-1)) raw_rho[k] ~ beta(p_rho[1],p_rho[2]);
  pi     ~ beta(p_pi[1],p_pi[2]);
  phi    ~ exponential(p_phi);
  xi_raw ~ beta(p_xi[1],p_xi[2]); 
  nu     ~ exponential(p_nu);
  psi    ~ beta(p_psi[1],p_psi[2]);
  //|_ Debug ----
  if(doprint==1) {
    print("beta: ",beta);
    print("eta: ",beta);
    print("epsilon: ",epsilon);
    print("rho: ",rho);
    print("pi: ",pi);
    print("y[5,]: ",y[5,]);
    print("comp_C[5,]: ",comp_C[5,]);
    print("comp_diffC[5,]: ",comp_diffC[5,]);
    print("comp_M[5,]: ",comp_M[5,]);
    print("comp_diffM[5,]: ",comp_diffM[5,]);
  }
  // |_ Likelihood ----
  if (inference!= 0) {
    for(i in 1:S) { // repeat for every day in the model
      target += neg_binomial_2_lpmf( incidence_cases[i] | 
          output_incidence_cases[i], output_incidence_cases[i]/phi[1]);
      target += neg_binomial_2_lpmf( incidence_deaths[i] | 
          output_incidence_deaths[i], output_incidence_deaths[i]/phi[2]);
    }
    target += multinomial_lpmf(genderdistr_cases | output_genderdistr_cases);
    target += multinomial_lpmf(genderdistr_deaths | output_genderdistr_deaths);
  }
}

// ------------------
generated quantities{
  real avg_rho = sum(gender_dist .* rho);
  real beta2 = beta*eta;
  real mu = (1-q_P)/(gt-1/tau_1-1/tau_2);
  real kappa = (q_P*tau_2*psi)/((1-q_P)*mu-(1-psi)*q_P*tau_2);

  int  predicted_reported_incidence_symptomatic_cases[S]; 
  real predicted_overall_incidence_symptomatic_cases[S]; 
  real predicted_overall_incidence_all_cases[S]; 
  int  predicted_reported_incidence_deaths[S+G];
  real predicted_overall_incidence_deaths[S+G];
  real compartment_data[S, K*6];
  
  int predicted_comp_reported_diffC[S,K];
  vector[K] predicted_comp_overall_diffC[S];
  vector[K] predicted_comp_overall_diffA[S];
  int predicted_comp_diffM[S+G,K];
  
  vector[K] predicted_total_reported_symptomatic_cases_by_gender;
  vector[K] predicted_total_overall_symptomatic_cases_by_gender;
  vector[K] predicted_total_overall_all_cases_by_gender;
  vector[K] predicted_total_overall_deaths_tmax_by_gender;
  vector[K] predicted_total_overall_deaths_delay_by_gender;
  
  real predicted_total_reported_symptomatic_cases;
  real predicted_total_overall_symptomatic_cases;
  real predicted_total_overall_all_cases;
  real predicted_total_overall_deaths_tmax;
  real predicted_total_overall_deaths_delay;
  
  vector[K] cfr_A_symptomatic_by_gender; //cfr by age classes, no correction of underreporting, no correction of time lag
  vector[K] cfr_B_symptomatic_by_gender; //cfr by age classes, no correction of underreporting, correction of time lag
  vector[K] cfr_C_symptomatic_by_gender; //cfr by age classes, correction of underreporting, no correction of time lag
  vector[K] cfr_D_symptomatic_by_gender; //cfr by age classes, correction of underreporting, correction of time lag
  vector[K] cfr_C_all_by_gender; //cfr by age classes, correction of underreporting and asymptomatics, no correction of time lag
  vector[K] cfr_D_all_by_gender; //cfr by age classes, correction of underreporting and asymptomatics, correction of time lag
  real cfr_A_symptomatic; //cfr by age classes, no correction of underreporting, no correction of time lag
  real cfr_B_symptomatic; //cfr by age classes, no correction of underreporting, correction of time lag
  real cfr_C_symptomatic; //cfr by age classes, correction of underreporting, no correction of time lag
  real cfr_D_symptomatic; //cfr by age classes, correction of underreporting, correction of time lag
  real cfr_C_all; //cfr by age classes, correction of underreporting and asymptomatics, no correction of time lag
  real cfr_D_all; //cfr by age classes, correction of underreporting and asymptomatics, correction of time lag
  
  for(i in 1:S){
    predicted_reported_incidence_symptomatic_cases[i] = neg_binomial_2_rng(sum(comp_diffC[i].*rho)*p_underreport_cases, sum(comp_diffC[i].*rho)*p_underreport_cases/phi[1]);
    predicted_overall_incidence_symptomatic_cases[i] = predicted_reported_incidence_symptomatic_cases[i] / p_underreport_cases / avg_rho;
    predicted_overall_incidence_all_cases[i] = predicted_reported_incidence_symptomatic_cases[i] / p_underreport_cases / avg_rho / psi;
  }

  // Output the raw compartmental model to visualize SEPAIR model
  compartment_data = y;
  
  
  for(i in 1:(S+G)) {
    predicted_reported_incidence_deaths[i] = neg_binomial_2_rng(sum(comp_diffM[i])*p_underreport_deaths, sum(comp_diffM[i])*p_underreport_deaths/phi[2]);
    predicted_overall_incidence_deaths[i] = (1e-9+predicted_reported_incidence_deaths[i]) / p_underreport_deaths;
  }
  for(i in 1:S) {
    predicted_comp_reported_diffC[i] = 
      predicted_reported_incidence_symptomatic_cases[i] == 0 ? rep_array(0,K) : 
      multinomial_rng(output_genderdistr_cases,predicted_reported_incidence_symptomatic_cases[i]);
    predicted_comp_overall_diffC[i] = 
      to_vector(predicted_comp_reported_diffC[i]) ./ rho / p_underreport_cases;
    predicted_comp_overall_diffA[i] = 
      to_vector(predicted_comp_reported_diffC[i]) ./ rho * (1-psi) / psi / 
      p_underreport_cases;
  }
  for(i in 1:(S+G)) predicted_comp_diffM[i] = predicted_reported_incidence_deaths[i] == 0 ?
    rep_array(0,K) : multinomial_rng(output_genderdistr_deaths, 
    predicted_reported_incidence_deaths[i]);
    
  for(i in 1:K) {
    predicted_total_reported_symptomatic_cases_by_gender[i] = 
      sum(predicted_comp_reported_diffC[1:S,i]) ;
    predicted_total_overall_symptomatic_cases_by_gender[i] = 
      sum(predicted_comp_overall_diffC[1:S,i]);
    predicted_total_overall_all_cases_by_gender[i] = 
      sum(predicted_comp_overall_diffC[1:S,i]) + sum(predicted_comp_overall_diffA[1:S,i]);
    predicted_total_overall_deaths_tmax_by_gender[i] = 
      sum(predicted_comp_diffM[1:S,i]) / p_underreport_deaths;
    predicted_total_overall_deaths_delay_by_gender[i] = 
      sum(predicted_comp_diffM[1:(S+G),i]) / p_underreport_deaths;
  }
  predicted_total_reported_symptomatic_cases = 
    sum(predicted_total_reported_symptomatic_cases_by_gender);
  predicted_total_overall_symptomatic_cases = 
    sum(predicted_total_overall_symptomatic_cases_by_gender);
  predicted_total_overall_all_cases = 
    sum(predicted_total_overall_all_cases_by_gender);
  predicted_total_overall_deaths_tmax = 
    sum(predicted_total_overall_deaths_tmax_by_gender);
  predicted_total_overall_deaths_delay = 
    sum(predicted_total_overall_deaths_delay_by_gender);
  
  cfr_A_symptomatic_by_gender = 
    predicted_total_overall_deaths_tmax_by_gender ./ predicted_total_reported_symptomatic_cases_by_gender;
  cfr_B_symptomatic_by_gender = 
    predicted_total_overall_deaths_delay_by_gender ./ predicted_total_reported_symptomatic_cases_by_gender;
  cfr_C_symptomatic_by_gender = 
    predicted_total_overall_deaths_tmax_by_gender ./ predicted_total_overall_symptomatic_cases_by_gender;
  cfr_D_symptomatic_by_gender = 
    predicted_total_overall_deaths_delay_by_gender ./ predicted_total_overall_symptomatic_cases_by_gender;
  
  cfr_A_symptomatic = 
    predicted_total_overall_deaths_tmax / predicted_total_reported_symptomatic_cases;
  cfr_B_symptomatic = 
    predicted_total_overall_deaths_delay / predicted_total_reported_symptomatic_cases;
  cfr_C_symptomatic = 
    predicted_total_overall_deaths_tmax / predicted_total_overall_symptomatic_cases;
  cfr_D_symptomatic = 
    predicted_total_overall_deaths_delay / predicted_total_overall_symptomatic_cases;
  
  cfr_C_all_by_gender = predicted_total_overall_deaths_tmax_by_gender ./ predicted_total_overall_all_cases_by_gender;
  cfr_D_all_by_gender = predicted_total_overall_deaths_delay_by_gender ./ predicted_total_overall_all_cases_by_gender;
  
  cfr_C_all = predicted_total_overall_deaths_tmax / predicted_total_overall_all_cases;
  cfr_D_all = predicted_total_overall_deaths_delay / predicted_total_overall_all_cases;
}
