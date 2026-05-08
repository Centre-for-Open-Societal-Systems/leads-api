package com.registry.verg.leads.repository;

import com.registry.verg.leads.entity.LeadsEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface LeadsRepository extends JpaRepository<LeadsEntity, String> {

}