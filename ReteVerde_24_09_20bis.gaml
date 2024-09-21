/**
* Name: ReteVerde240920bis
* Based on the internal empty template. 
* Author: pccal
* Tags: 
*/


model ReteVerde240920bis

/* Insert your model definition here */

global {
    string parks <- "../includes/LastAllCircNew/CUTAllmGreenIntersect.shp";
    string buildings <- "../includes/LastAllCircNew/CUTAllmBuildingNew.shp";
    string bordo <- "../includes/LastAllCircNew/CUTAllmBordo.shp";

    file shape_file_parks <- file(parks);
    file shape_file_buildings <- file(buildings);
    file shape_file_bordo <- file(bordo);
    geometry shape <- envelope(shape_file_bordo);

    float point_distances <- 20.0 #m; // Distanza tra i punti da campionare
    float max_links_length <- 35.0 #m;
    float aura_width <- 10.0 #m;
    
    // Variabile globale per il controllo di attraversamento
    bool global_crossing_check <- false;
    
    init {
        create park from: shape_file_parks;
        ask park {
            do update_neighbors;
            do sample_points;
            do agents_points_inside;
            do create_links;
            do update_link_stats;
            do count_sampled; // Aggiungi la chiamata alla nuova funzione
            do links_and_weight;
        }
        create building from: shape_file_buildings;
    }
}

species park {
    geometry geom;
    geometry aura;
    geometry perimetro;
    rgb color <- #green;
    list<park> neighbor_parks <- [];//Vicini secondo l'aura
    int nb_neighbor; //numero di vicini secondo l'aura
    int nb_agents_points; //numero di punti campionati sul perimetro
    list<sample_point> sampled_points_agents <- []; //lista dei punti come agenti
    list<point> sampled_points <- []; //lista dei punti come punti
    list<geometry> links_with_neighbors <- [];  // Lista dei collegamenti
    list<float> link_weights <- [];  // Pesi dei link
    int nb_neighbor_links; //numero di vicini collegati dai link
    int nb_points_affecting_other_parks; //numero di punti che affacciano su altri parchi
    list<park> parks_with_links <- []; // Nuova lista per i parchi vicini di link
    list<point> points_affecting_other_parks <- []; // Nuova lista per i punti che affacciano su altri parchi
    list<park> all_parks_with_links <-[]; //Lista per tenere tutti i parchi collegati dai link con ripetizioni
    
    int grade;//numero di vicini, il grado
   	list<int> freq<-[];//frequenze con cui si collega ai vicini coi link
   	list<float> wei<-[];//pesi dei link
   	float openess; //percentuale di punti con sbocco su altri parchi
    
    
    init {
        geom <- shape;
        aura <- aura_width around geom;
        perimetro <- geom.contour;
    }

    // Azione per campionare i punti sul perimetro
    action sample_points {
        // Campiona i punti lungo il perimetro alla distanza definita
        sampled_points <- perimetro points_on(point_distances);
        int nb_points <- length(sampled_points);

        // Crea agenti per i punti campionati
        if (nb_points > 0) {
            loop i from: 0 to: nb_points - 1 {
                create sample_point {
                    location <- myself.sampled_points[i];
                }
            }
        } else {
            // Crea almeno un punto in posizione fissa se nessun punto viene campionato
            create sample_point {
                location <- myself.location;
            }
        }
    }

    action update_neighbors {
        neighbor_parks <- park at_distance aura_width - self;
        nb_neighbor <- length(neighbor_parks);
        if (nb_neighbor = 0) {
            color <- #red;
        }
    }
    
    // Azione per far eseguire un'azione ai punti campionati
    action loop_sampled_points {
    	
        if (length(sampled_points_agents) > 0) {
            loop each_agent over: sampled_points_agents {
                ask each_agent {
                    host_park <- myself;
                    self.neighbor_parks <- myself.neighbor_parks;
                    do point_in_action;
                }
            }
        }
    }
    
    // Azione per instanziare la lista di agenti sample_point che appartengono al parco
    action agents_points_inside {
        sampled_points_agents <- sample_point inside self;
        
    }
    
    // Azione per verificare se una linea attraversa edifici o il parco stesso
    action check_crossing(point p1, point p2) {
        // Crea una linea tra i due punti
        geometry line <- line(p1, p2);
        
        // Controlla se la linea attraversa edifici
        global_crossing_check <- false;
        ask building {
            if (geom intersects line) {
                global_crossing_check <- true;
            }
        }

        // Controlla se la linea attraversa il parco stesso
        //ELIMINO 
        //if (geom intersects line) {
          //  global_crossing_check <- true;
       // }
    }
    
    // Azione per creare i link tra i punti dei parchi vicini
    action create_links {
        // Loop sui punti campionati
        loop each_point over: sampled_points {
            loop each_neighbor over: neighbor_parks {
                // Prendi i punti del parco vicino
                list<point> neighbor_points <- each_neighbor.sampled_points;
                
                // Loop sui punti del parco vicino
                loop each_neighbor_point over: neighbor_points {
                    float distance <- each_point distance_to each_neighbor_point;
                    
                    // Verifica se la distanza è inferiore alla soglia e se il link non attraversa un edificio o il parco stesso
                    do check_crossing(each_point, each_neighbor_point);
                    if (distance < max_links_length and not global_crossing_check) {
                        // Crea il link e lo aggiunge alla lista dei collegamenti
                        geometry new_link <- line(each_point, each_neighbor_point);
                        links_with_neighbors <- links_with_neighbors + new_link;

                        // Aggiungi il peso del link
                        int num_links <- length(links_with_neighbors);
                        float link_weight <- num_links / length(sampled_points);  // Peso del link
                        link_weights <- link_weights + link_weight;
                    }
                }
            }
        }
    }
    action count_sampled {
    	nb_agents_points<-length(sampled_points_agents);
    }

    // Nuova azione per aggiornare le statistiche sui link
    action update_link_stats {
        list<point> unique_p1 <- [];  // Lista dei punti p1 unici
        list<point> p2_list <- [];    // Lista di tutti i punti p2
        list<park> unique_parks <- []; // Lista dei parchi unici associati a p2
        list<park> all_parks_linked<-[]; 

        // Reset delle variabili
        nb_neighbor_links <- 0;
        nb_points_affecting_other_parks <- 0;

        // Loop sui link e aggiornamento delle statistiche
        loop each_link over: links_with_neighbors {
            // Ottieni i punti della polyline (linea)
            list<point> points <- each_link.points;

            // Assicurati che ci siano almeno due punti per definire una linea
            if (length(points) > 1) {
                point p1 <- points[0]; // Primo punto della polyline
                point p2 <- points[1]; // Secondo punto della polyline
            
                // Aggiungi p1 alla lista se non è già presente
                if (not (p1 in unique_p1)) {
                    unique_p1 <- unique_p1 + p1;
                }
            
                // Aggiungi p2 alla lista p2_list
                p2_list <- p2_list + p2;
            }
        }
    
    // Ora chiediamo ai parchi vicini se hanno uno dei punti in p2_list
    loop each_neighbor over: neighbor_parks {
        ask each_neighbor {
            loop each_p2 over: p2_list {
                // Se il punto p2 è tra i punti campionati del parco vicino, aggiungiamo il parco alla lista unica
                if (each_p2 in sampled_points) {
                	all_parks_linked<-all_parks_linked+self;
                    if (not (self in unique_parks)) { //per ottenere una lista con tutte le occorrenze e riuscire a 
                        unique_parks <- unique_parks + self;
                    }
                }
            }
        }
    }
    
    // Aggiorna le variabili con i risultati
    nb_neighbor_links <- length(unique_parks);  // Numero di parchi vicini collegati tramite link
    nb_points_affecting_other_parks <- length(unique_p1);  // Numero di punti p1 che affacciano su altri parchi
    parks_with_links <- unique_parks;  // Nuova lista per i parchi vicini di link
    all_parks_with_links<-all_parks_linked;
    points_affecting_other_parks <- unique_p1; // Lista per i punti che affacciano su altri parchi
    
}
    
   action links_and_weight{
   	list<int> frequencies<-[];
   	list<float> weights<-[];
   	float coeff_affaccio<-nb_points_affecting_other_parks/nb_agents_points;
   	int grado<-nb_neighbor_links;
   	int nb_total_points<-nb_agents_points;
   	loop each_neighbor over:parks_with_links{
   		int w<-0;
   		int ww<-0;
   		loop each_park over:all_parks_with_links{
   			if(each_park=each_neighbor){w<-w+1;}
   		}
   		frequencies<-frequencies+w; //il primo peso è riferito all'ordine di parks_with_links
   		ww<-w/nb_total_points;
   		weights<-weights+ww;
   	}
   	
   	grade<-grado;
   	freq<-frequencies;
   	wei<-weights;
   	openess<-coeff_affaccio;
   } 

    
    aspect base {
        draw geom color: color;
        draw aura color: color border: #black wireframe: true;
        draw perimetro color: #gold;
    }
}

species building {
    geometry geom;
    rgb color <- #gray;
    
    init {
        geom <- shape;
    }
    
    aspect base {
        draw geom color: color;
    }
}

// Nuova specie per rappresentare i punti campionati
species sample_point {
    point location;
    park host_park;             // Riferimento al parco che contiene il punto
    list<park> neighbor_parks;  // Lista dei parchi vicini
    
    aspect base {
        draw circle(4) at: location color: #blue;
    }
    
    action point_in_action {
        // Implementazione futura
    }
    
    action ask_neighbor {
        // Implementazione futura
    }
}

experiment Rete type: gui {
    output {
        display MyDisplay type: java2D {
            species park aspect: base transparency: 0;
            species building aspect: base transparency: 0.3;
            species sample_point aspect: base;  // Aggiungi i punti campionati al display
        }
        
        monitor "Total parks" value: length(park);
        monitor "Parks with neighbors" value: park count (length(each.neighbor_parks) > 0);
        monitor "Link weights per park" value: park count (length(each.link_weights) > 0);
       // monitor "Number of neighbor parks linked" value: park nb_neighbor_links;
       // monitor "Number of points affecting other parks" value: park nb_points_affecting_other_parks;
    }
}